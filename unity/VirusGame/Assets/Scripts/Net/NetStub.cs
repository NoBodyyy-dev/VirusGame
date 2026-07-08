using System;
using UnityEngine;

namespace Virus.Net
{
    // ЗАГЛУШКА кооп-сети. Godot net.gd (730 строк) построен на встроенном
    // высокоуровневом мультиплеере (@rpc, авторитет, «хост владеет состоянием»).
    // В Unity встроенного эквивалента НЕТ — это отдельный редизайн на
    // Netcode for GameObjects (NGO), Mirror или Fish-Net:
    //   • net.gd RPC (@rpc any_peer/authority) → [ServerRpc] / [ClientRpc] в NetworkBehaviour
    //   • host_hp / loot_state / enemy_tf синки → NetworkVariable<T> / NetworkTransform
    //   • sync_identity / players dict → NetworkList + подключение колбэков
    //   • GameState.SetFlag(...).SendFlag хук → ServerRpc, рассылающий флаг всем
    // Пока — одиночный режим: active=false, все хуки no-op.
    public static class NetStub
    {
        public static bool active = false;
        public static bool IsServer() => true;

        // подключается к GameState.I.SendFlag в одиночке (ничего не делает)
        public static Action<string> FlagSender = _ => { };
    }
}
