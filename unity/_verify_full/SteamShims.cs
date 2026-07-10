// Шимы Steamworks.NET: только сигнатуры, используемые Net/SteamNet.cs.
// Поведение не эмулируется — цель одна: ловить ошибки компиляции без Unity.
using System;

namespace Steamworks
{
    public struct CSteamID : IEquatable<CSteamID>
    {
        public ulong m_SteamID;
        public CSteamID(ulong id) { m_SteamID = id; }
        public static readonly CSteamID Nil = new CSteamID(0);
        public bool IsValid() => m_SteamID != 0;
        public bool Equals(CSteamID other) => m_SteamID == other.m_SteamID;
        public override bool Equals(object o) => o is CSteamID c && Equals(c);
        public override int GetHashCode() => m_SteamID.GetHashCode();
    }

    public struct SteamAPICall_t { public ulong m_SteamAPICall; }

    public enum EResult { k_EResultOK = 1, k_EResultFail = 2 }
    public enum ELobbyType { k_ELobbyTypePrivate, k_ELobbyTypeFriendsOnly, k_ELobbyTypePublic }
    public enum ELobbyComparison { k_ELobbyComparisonEqual = 0 }
    public enum EP2PSend { k_EP2PSendUnreliable, k_EP2PSendUnreliableNoDelay, k_EP2PSendReliable, k_EP2PSendReliableWithBuffering }

    public struct LobbyCreated_t { public EResult m_eResult; public ulong m_ulSteamIDLobby; }
    public struct LobbyEnter_t { public ulong m_ulSteamIDLobby; }
    public struct LobbyMatchList_t { public uint m_nLobbiesMatching; }
    public struct GameLobbyJoinRequested_t { public CSteamID m_steamIDLobby; public CSteamID m_steamIDFriend; }
    public struct P2PSessionRequest_t { public CSteamID m_steamIDRemote; }
    public struct P2PSessionConnectFail_t { public CSteamID m_steamIDRemote; public byte m_eP2PSessionError; }

    public class Callback<T>
    {
        public static Callback<T> Create(Action<T> fn) => new Callback<T>();
    }

    public class CallResult<T>
    {
        public static CallResult<T> Create(Action<T, bool> fn) => new CallResult<T>();
        public void Set(SteamAPICall_t call) { }
    }

    public static class SteamAPI
    {
        public static bool Init() => false;
        public static void RunCallbacks() { }
        public static void Shutdown() { }
    }

    public static class SteamUser
    {
        public static CSteamID GetSteamID() => CSteamID.Nil;
    }

    public static class SteamFriends
    {
        public static string GetPersonaName() => "";
    }

    public static class SteamMatchmaking
    {
        public static SteamAPICall_t CreateLobby(ELobbyType t, int maxMembers) => default;
        public static bool SetLobbyData(CSteamID lobby, string key, string value) => true;
        public static void AddRequestLobbyListStringFilter(string key, string value, ELobbyComparison cmp) { }
        public static SteamAPICall_t RequestLobbyList() => default;
        public static CSteamID GetLobbyByIndex(int i) => CSteamID.Nil;
        public static SteamAPICall_t JoinLobby(CSteamID lobby) => default;
        public static CSteamID GetLobbyOwner(CSteamID lobby) => CSteamID.Nil;
        public static void LeaveLobby(CSteamID lobby) { }
    }

    public static class SteamNetworking
    {
        public static bool SendP2PPacket(CSteamID remote, byte[] data, uint len, EP2PSend send, int channel = 0) => true;
        public static bool IsP2PPacketAvailable(out uint size, int channel = 0) { size = 0; return false; }
        public static bool ReadP2PPacket(byte[] dest, uint destLen, out uint read, out CSteamID remote, int channel = 0)
        { read = 0; remote = CSteamID.Nil; return false; }
        public static bool AcceptP2PSessionWithUser(CSteamID remote) => true;
    }
}
