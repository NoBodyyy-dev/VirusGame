#if STEAMWORKS_NET
using System.Collections.Generic;
using System.IO;
using Steamworks;
using UnityEngine;
using Virus.Core;

namespace Virus.Net
{
    // Steam-транспорт кооп-стаи (Steamworks.NET, UPM-пакет из manifest.json):
    // лобби + legacy P2P-пакеты. Протокол тот же строковый NetSync, что и по
    // TCP — пир хранит steam-id вместо сокета, SendTo/Handle общие.
    // AppId 480 (Spacewar) — тестовый; при релизе вписать свой в steam_appid.txt
    // и в RestartAppIfNecessary. Весь файл компилируется только при
    // STEAMWORKS_NET (define ставит UnityBuild, если пакет установлен).
    public partial class NetManager
    {
        const int SteamChannel = 0;

        static bool _steamInited;
        CSteamID _lobby;
        readonly Dictionary<ulong, Peer> _steamPeers = new();
        byte[] _steamBuf = new byte[8192];

        Callback<LobbyCreated_t> _cbLobbyCreated;
        Callback<LobbyEnter_t> _cbLobbyEnter;
        Callback<GameLobbyJoinRequested_t> _cbJoinRequested;
        Callback<P2PSessionRequest_t> _cbP2PRequest;
        Callback<P2PSessionConnectFail_t> _cbP2PFail;
        CallResult<LobbyMatchList_t> _crLobbyList;

        partial void SteamInitImpl()
        {
            if (_steamInited) { _steamReady = true; return; }
            try
            {
                // steam_appid.txt рядом с exe — иначе Init() вне запуска из Steam падает
                var appid = Path.Combine(Path.GetDirectoryName(Application.dataPath) ?? ".", "steam_appid.txt");
                if (!File.Exists(appid)) File.WriteAllText(appid, "480");
            }
            catch { }
            try { _steamInited = SteamAPI.Init(); }
            catch (System.DllNotFoundException) { _steamInited = false; }
            _steamReady = _steamInited;
            if (!_steamInited)
            {
                Debug.Log("[SteamNet] Steam недоступен (клиент не запущен?) — только LAN");
                return;
            }
            _cbLobbyCreated = Callback<LobbyCreated_t>.Create(OnLobbyCreated);
            _cbLobbyEnter = Callback<LobbyEnter_t>.Create(OnLobbyEnter);
            _cbJoinRequested = Callback<GameLobbyJoinRequested_t>.Create(
                r => SteamMatchmaking.JoinLobby(r.m_steamIDLobby));
            _cbP2PRequest = Callback<P2PSessionRequest_t>.Create(
                r => SteamNetworking.AcceptP2PSessionWithUser(r.m_steamIDRemote));
            _cbP2PFail = Callback<P2PSessionConnectFail_t>.Create(OnP2PFail);
            _crLobbyList = CallResult<LobbyMatchList_t>.Create(OnLobbyList);
            Debug.Log("[SteamNet] Steam инициализирован: " + SteamFriends.GetPersonaName());
        }

        partial void SteamHostImpl()
        {
            if (!_steamInited) { Toast("Steam недоступен — стая только по LAN"); return; }
            SteamMatchmaking.CreateLobby(ELobbyType.k_ELobbyTypePublic, 8);
        }

        void OnLobbyCreated(LobbyCreated_t r)
        {
            if (r.m_eResult != EResult.k_EResultOK) { Toast("Steam: не удалось создать лобби"); return; }
            _lobby = new CSteamID(r.m_ulSteamIDLobby);
            SteamMatchmaking.SetLobbyData(_lobby, "vg", "1");
            SteamMatchmaking.SetLobbyData(_lobby, "host", SteamFriends.GetPersonaName());
            Toast("Steam-лобби создано — зовите стаю (Shift+Tab → пригласить)");
        }

        partial void SteamJoinImpl()
        {
            if (!_steamInited) { Toast("Steam недоступен"); return; }
            if (_joined || _isHost) return;
            SteamMatchmaking.AddRequestLobbyListStringFilter("vg", "1", ELobbyComparison.k_ELobbyComparisonEqual);
            _crLobbyList.Set(SteamMatchmaking.RequestLobbyList());
            Toast("Steam: ищем лобби стаи…");
        }

        void OnLobbyList(LobbyMatchList_t r, bool ioFail)
        {
            if (ioFail || r.m_nLobbiesMatching == 0)
            {
                Toast("Steam: лобби не найдено — хост должен создать стаю");
                return;
            }
            SteamMatchmaking.JoinLobby(SteamMatchmaking.GetLobbyByIndex(0));
        }

        void OnLobbyEnter(LobbyEnter_t r)
        {
            _lobby = new CSteamID(r.m_ulSteamIDLobby);
            if (_isHost) return;   // вошли в собственное лобби
            var owner = SteamMatchmaking.GetLobbyOwner(_lobby);
            if (owner.m_SteamID == SteamUser.GetSteamID().m_SteamID) return;
            _joined = true;
            var peer = new Peer { steam = owner.m_SteamID };
            _host = peer;
            _steamPeers[owner.m_SteamID] = peer;
            var s = GameState.I;
            SendTo(peer, NetSync.MsgHello(_myName, s.branch, s.virusLevel, s.secondaryBranch));
            Toast("Steam: подключаемся к хосту стаи…");
        }

        // читается в Update главного потока — Handle можно звать напрямую
        partial void SteamPollImpl()
        {
            if (!_steamInited) return;
            SteamAPI.RunCallbacks();
            while (SteamNetworking.IsP2PPacketAvailable(out uint size, SteamChannel))
            {
                if (size > _steamBuf.Length) _steamBuf = new byte[size];
                if (!SteamNetworking.ReadP2PPacket(_steamBuf, (uint)_steamBuf.Length,
                        out uint read, out CSteamID remote, SteamChannel)) break;
                var peer = SteamPeer(remote.m_SteamID);
                foreach (var line in peer.framer.Feed(_steamBuf, (int)read))
                    Handle(peer, line);
            }
        }

        Peer SteamPeer(ulong id)
        {
            if (_steamPeers.TryGetValue(id, out var p)) return p;
            p = new Peer { steam = id };
            if (_isHost)
                lock (_peers) { p.id = _nextId++; _peers.Add(p); }
            _steamPeers[id] = p;
            return p;
        }

        partial void SteamSendImpl(ulong steamId, byte[] data)
        {
            if (!_steamInited) return;
            SteamNetworking.SendP2PPacket(new CSteamID(steamId), data, (uint)data.Length,
                EP2PSend.k_EP2PSendReliable, SteamChannel);
        }

        void OnP2PFail(P2PSessionConnectFail_t r)
        {
            if (!_steamPeers.TryGetValue(r.m_steamIDRemote.m_SteamID, out var p)) return;
            _steamPeers.Remove(r.m_steamIDRemote.m_SteamID);
            p.alive = false;
            _inbox.Enqueue((p, "GONE"));
        }

        partial void SteamShutdownImpl()
        {
            if (!_steamInited) return;
            if (_lobby.IsValid()) { SteamMatchmaking.LeaveLobby(_lobby); _lobby = CSteamID.Nil; }
            _steamPeers.Clear();
            // SteamAPI.Shutdown() намеренно не зовём: NetManager может пересоздаться
        }
    }
}
#endif
