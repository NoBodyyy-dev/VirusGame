using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using UnityEngine;
using Virus.Core;
using Virus.Util;

namespace Virus.Net
{
    // Кооп по LAN (редизайн net.gd): хост владеет кампанией, клиенты получают
    // снапшот и живые события (флаги, захваты узлов), все обмениваются позицией
    // и идентичностью штамма. Транспорт — TCP: поток чтения на пира, строки
    // режет Core.NetFramer, применение к состоянию — Core.NetSync (main thread).
    public class NetManager : MonoBehaviour
    {
        public static NetManager I { get; private set; }
        public static bool Active => I != null && (I._isHost || I._joined);

        class Peer
        {
            public int id;
            public TcpClient tcp;
            public NetworkStream stream;
            public readonly NetFramer framer = new();
            public volatile bool alive = true;
        }

        class Avatar
        {
            public int id, stage;
            public string name = "ШТАММ", cls = "base", sec = "", scene = "", sig = "";
            public GameObject go;
            public TextMesh label;
            public Vector3 target;
            public float ry;
        }

        bool _isHost, _joined;
        TcpListener _listener;
        Peer _host;                                // у клиента: соединение с хостом
        readonly List<Peer> _peers = new();        // у хоста: клиенты
        readonly ConcurrentQueue<(Peer from, string line)> _inbox = new();
        readonly Dictionary<int, Avatar> _avatars = new();
        int _nextId = 2;
        public int myId = 1;
        string _myName;
        float _posTimer;
        bool _identityDirty = true;
        Player.VirusPlayer _localPlayer;
        UI.Hud _hud;

        static NetManager Ensure()
        {
            if (I == null) new GameObject("NetManager", typeof(NetManager));
            return I;
        }

        public static void StartHost() => Ensure().HostGame();
        public static void StartClient(string ip) => Ensure().JoinGame(ip);

        void Awake()
        {
            if (I != null && I != this) { Destroy(gameObject); return; }
            I = this;
            DontDestroyOnLoad(gameObject);
            _myName = "ШТАММ-" + new System.Random().Next(100, 999);
            GameState.I.SendFlag += key => Broadcast(NetSync.MsgFlag(key));
            GameState.I.SendNodeInfected += id => Broadcast(NetSync.MsgNode(id));
            GameState.I.EvolutionChanged += () => _identityDirty = true;
        }

        // ── запуск ──
        void HostGame()
        {
            if (_isHost) return;
            _isHost = true;
            myId = 1;
            _listener = new TcpListener(IPAddress.Any, NetSync.Port);
            _listener.Start();
            new Thread(AcceptLoop) { IsBackground = true }.Start();
        }

        void JoinGame(string ip)
        {
            if (_joined || _isHost) return;
            _joined = true;
            var peer = new Peer();
            _host = peer;
            new Thread(() =>
            {
                try
                {
                    peer.tcp = new TcpClient();
                    peer.tcp.Connect(ip, NetSync.Port);
                    peer.stream = peer.tcp.GetStream();
                    var s = GameState.I;
                    SendTo(peer, NetSync.MsgHello(_myName, s.branch, s.virusLevel, s.secondaryBranch));
                    ReadLoop(peer);
                }
                catch { peer.alive = false; }
            }) { IsBackground = true }.Start();
        }

        void AcceptLoop()
        {
            while (_isHost)
            {
                try
                {
                    var tcp = _listener.AcceptTcpClient();
                    var peer = new Peer { tcp = tcp, stream = tcp.GetStream() };
                    lock (_peers) { peer.id = _nextId++; _peers.Add(peer); }
                    new Thread(() => ReadLoop(peer)) { IsBackground = true }.Start();
                }
                catch { break; }
            }
        }

        void ReadLoop(Peer peer)
        {
            var buf = new byte[4096];
            try
            {
                while (peer.alive)
                {
                    int n = peer.stream.Read(buf, 0, buf.Length);
                    if (n <= 0) break;
                    foreach (var line in peer.framer.Feed(buf, n))
                        _inbox.Enqueue((peer, line));
                }
            }
            catch { }
            peer.alive = false;
            _inbox.Enqueue((peer, "GONE"));
        }

        // ── отправка (из главного потока) ──
        void SendTo(Peer peer, string msg)
        {
            if (peer?.stream == null || !peer.alive) return;
            try
            {
                var data = NetFramer.Pack(msg);
                lock (peer) peer.stream.Write(data, 0, data.Length);
            }
            catch { peer.alive = false; }
        }

        void Broadcast(string msg, Peer except = null)
        {
            if (!Active) return;
            if (_isHost)
            {
                lock (_peers)
                    foreach (var p in _peers)
                        if (p != except) SendTo(p, msg);
            }
            else if (_host != null && _host != except) SendTo(_host, msg);
        }

        // ── главный поток: применение входящих и рассылка позиции ──
        void Update()
        {
            while (_inbox.TryDequeue(out var item)) Handle(item.from, item.line);

            if (!Active) return;
            _posTimer -= Time.deltaTime;
            if (_posTimer <= 0f)
            {
                _posTimer = 0.12f;
                SendMyState();
            }
            string myScene = SceneToken();
            foreach (var a in _avatars.Values) UpdateAvatarVisual(a, myScene);
        }

        string SceneToken()
        {
            string name = UnityEngine.SceneManagement.SceneManager.GetActiveScene().name;
            return name switch
            {
                "GridWorld" => "grid",
                "Level" => "raid:" + (GameState.I.currentNode?.id ?? -1),
                "VictoryTunnel" => "victory",
                _ => "menu",
            };
        }

        void SendMyState()
        {
            if (_localPlayer == null) _localPlayer = FindFirstObjectByType<Player.VirusPlayer>();
            var s = GameState.I;
            if (_identityDirty)
            {
                _identityDirty = false;
                Broadcast(NetSync.MsgIdentity(myId, _myName, s.DisplayClass(), s.EvolveStage(), s.DisplaySecondary()));
            }
            if (_localPlayer == null) return;
            var p = _localPlayer.transform.position;
            var ry = _localPlayer.LookDir();
            Broadcast(NetSync.MsgPos(myId, SceneToken(), p.x, p.y, p.z, Mathf.Atan2(ry.x, ry.z) * Mathf.Rad2Deg));
        }

        // ── обработка сообщений ──
        void Handle(Peer from, string line)
        {
            if (line == "GONE") { OnPeerGone(from); return; }
            var p = NetSync.Parse(line);
            var s = GameState.I;
            switch (p[0])
            {
                case "HI":   // только хост: новичок представился
                    if (!_isHost || p.Length < 5) break;
                    var av = GetAvatar(from.id);
                    av.name = p[1];
                    av.cls = p[2] == "" ? "base" : p[2];
                    int.TryParse(p[3], out av.stage);
                    av.sec = p[4];
                    SendTo(from, NetSync.MsgId(from.id));
                    SendTo(from, NetSync.MsgSnapshot(s));
                    // новичку — все известные личности (включая хоста)
                    SendTo(from, NetSync.MsgIdentity(myId, _myName, s.DisplayClass(), s.EvolveStage(), s.DisplaySecondary()));
                    foreach (var other in _avatars.Values)
                        if (other.id != from.id)
                            SendTo(from, NetSync.MsgIdentity(other.id, other.name, other.cls, other.stage, other.sec));
                    Broadcast(NetSync.MsgIdentity(from.id, av.name, av.cls, av.stage, av.sec), from);
                    Toast($"{av.name} подключился к стае");
                    break;
                case "ID":   // только клиент: наш id
                    if (int.TryParse(p[1], out var mid)) myId = mid;
                    Toast("Подключено: кампания стаи синхронизирована");
                    _identityDirty = true;
                    break;
                case "SNAP":
                    NetSync.ApplySnapshot(s, p);
                    break;
                case "FLAG":
                    NetSync.ApplyFlag(s, p);
                    if (_isHost) Broadcast(line, from);
                    break;
                case "NODE":
                    NetSync.ApplyNode(s, p);
                    if (_isHost) Broadcast(line, from);
                    Toast("Стая захватила сервер!");
                    Sfx.Play("deposit", 0.3f);
                    break;
                case "POS":
                    if (p.Length >= 7 && int.TryParse(p[1], out var pid) && pid != myId)
                    {
                        var a = GetAvatar(pid);
                        a.scene = p[2];
                        NetSync.ParseF(p[3], out a.target.x);
                        NetSync.ParseF(p[4], out a.target.y);
                        NetSync.ParseF(p[5], out a.target.z);
                        NetSync.ParseF(p[6], out a.ry);
                        if (_isHost) Broadcast(line, from);
                    }
                    break;
                case "IDY":
                    if (p.Length >= 6 && int.TryParse(p[1], out var iid) && iid != myId)
                    {
                        var a = GetAvatar(iid);
                        a.name = p[2];
                        a.cls = p[3] == "" ? "base" : p[3];
                        int.TryParse(p[4], out a.stage);
                        a.sec = p[5];
                        if (_isHost) Broadcast(line, from);
                    }
                    break;
                case "MSG":
                    if (p.Length >= 2) Toast(p[1]);
                    if (_isHost) Broadcast(line, from);
                    break;
                case "BYE":
                    if (p.Length >= 2 && int.TryParse(p[1], out var bid)) RemoveAvatar(bid);
                    if (_isHost) Broadcast(line, from);
                    break;
            }
        }

        void OnPeerGone(Peer peer)
        {
            if (_isHost)
            {
                lock (_peers) _peers.Remove(peer);
                RemoveAvatar(peer.id);
                Broadcast(NetSync.MsgBye(peer.id));
                Toast("Штамм отключился от стаи");
            }
            else if (peer == _host)
            {
                _joined = false;
                foreach (var id in new List<int>(_avatars.Keys)) RemoveAvatar(id);
                Toast("Связь с хостом потеряна — одиночный режим");
            }
        }

        Avatar GetAvatar(int id)
        {
            if (!_avatars.TryGetValue(id, out var a))
            {
                a = new Avatar { id = id };
                _avatars[id] = a;
            }
            return a;
        }

        void RemoveAvatar(int id)
        {
            if (_avatars.TryGetValue(id, out var a) && a.go != null) Destroy(a.go);
            _avatars.Remove(id);
        }

        // ── куклы напарников: скин ветки + имя, видны в общей сцене ──
        void UpdateAvatarVisual(Avatar a, string myScene)
        {
            bool visible = a.id != myId && a.scene == myScene && myScene != "menu";
            if (!visible)
            {
                if (a.go != null) { Destroy(a.go); a.go = null; a.sig = ""; }
                return;
            }
            string sig = $"{a.cls}:{a.stage}:{a.sec}:{a.name}";
            if (a.go == null || sig != a.sig)
            {
                if (a.go != null) Destroy(a.go);
                a.sig = sig;
                a.go = new GameObject($"avatar_{a.id}");
                a.go.transform.position = a.target;
                string cls = GameData.CLASSES.ContainsKey(a.cls) ? a.cls : "base";
                Player.VirusModel.Build(a.go.transform, cls, a.stage, a.sec);
                a.label = Build.Label(a.go.transform, a.name, new Vector3(0, 2.7f, 0), 2.6f, GameData.CLASSES[cls].color);
            }
            a.go.transform.position = Vector3.Lerp(a.go.transform.position, a.target,
                Mathf.Min(10f * Time.deltaTime, 1f));
            a.go.transform.rotation = Quaternion.Euler(0, a.ry, 0);
        }

        void Toast(string text)
        {
            if (_hud == null) _hud = FindFirstObjectByType<UI.Hud>();
            _hud?.Toast(text);
        }

        void OnApplicationQuit() => Shutdown();
        void OnDestroy() { if (I == this) Shutdown(); }

        void Shutdown()
        {
            _isHost = false;
            _joined = false;
            try { _listener?.Stop(); } catch { }
            lock (_peers)
            {
                foreach (var pr in _peers) { pr.alive = false; try { pr.tcp?.Close(); } catch { } }
                _peers.Clear();
            }
            if (_host != null) { _host.alive = false; try { _host.tcp?.Close(); } catch { } }
        }
    }
}
