using System;
using Virus.Core;

// Поведенческий самотест ядра правил (dotnet run в _verify/).
// Проверяет дерево эволюции, активки, кражу/возврат, комбо и вспомогательный взлом.
static class SelfTest
{
    static int _fails;

    static void Check(bool ok, string what)
    {
        if (!ok) { _fails++; Console.WriteLine($"  FAIL: {what}"); }
    }

    static int Main()
    {
        var s = GameState.I;

        // ── кампания с нуля ──
        s.NewCampaign();
        Check(s.branch == "" && s.virusLevel == 0, "старт: без ветки, УР.0");
        Check(s.activeAbilities.Count == 0 && s.MaxAbilitySlots() == 0, "старт: без активок и слотов");
        Check(s.TotalNodes() == 31 && s.ZoneOpen(0) && !s.ZoneOpen(1), "грид: 31 узел, открыта только зона 0");

        // ── выбор ветки: только одна ──
        Check(!s.ChooseBranch("base") && !s.ChooseBranch("nope"), "нельзя взять base/несуществующую");
        Check(s.ChooseBranch("worm"), "ветка worm выбрана");
        Check(!s.ChooseBranch("trojan"), "вторая ветка сразу — нельзя");

        // ── уровни и сигнатурная активка ──
        Check(!s.CanLevelUp(), "УР.1 без ресурсов не купить");
        s.resources["data_fragments"] = 60;
        Check(s.LevelUp() && s.virusLevel == 1, "УР.1 куплен");
        Check(s.resources["data_fragments"] == 0, "ресурсы списаны");
        Check(s.activeAbilities.Contains("dash"), "сигнатурный РЫВОК выдан");
        Check(s.MaxAbilitySlots() == 1, "УР.1 = 1 слот");

        // ── задания на глубину ветки ──
        Check(!s.CanPickAbility("haste"), "haste заперт (слот занят + задание)");
        Check(s.UnequipAbility("dash"), "откат: dash снят");
        Check(!s.CanPickAbility("haste"), "haste всё ещё заперт заданием (deposits 0/6)");
        s.career["deposits"] = 6;
        Check(s.CanPickAbility("haste") && s.PickAbility("haste"), "haste взят после 6 вносов");
        Check(s.PickAbility("dash") == false, "слотов больше нет");

        // ── УР.2 и УР.3 ──
        s.resources["data_fragments"] = 150; s.resources["code_samples"] = 1;
        Check(s.LevelUp() && s.virusLevel == 2, "УР.2 куплен");
        Check(s.PickAbility("dash") && s.activeAbilities.Count == 2, "2 активки на УР.2");
        s.resources["data_fragments"] = 280; s.resources["code_samples"] = 2; s.resources["mutagen"] = 1;
        Check(s.LevelUp() && s.virusLevel == 3, "УР.3 куплен");
        Check(!s.CanLevelUp(), "выше УР.3 нет");
        Check(Math.Abs(s.AbilityCost("dash") - 15f * 1.5f) < 0.01f, "апекс: расход BW ×1.5");

        // ── доп. ветка на УР.3 ──
        Check(!s.ChooseSecondary("worm"), "доп. ветка = не своя же");
        Check(s.ChooseSecondary("botnet") && s.DisplaySecondary() == "botnet", "доп. ветка botnet");
        Check(s.AbilityPool().Contains("heal"), "пул расширен умениями botnet");
        Check(s.HasPassive("botnet") && s.HasPassive("worm"), "обе пассивки активны");

        // ── кража перепрошивкой и возврат после рейда ──
        int before = s.activeAbilities.Count;
        string stolen = s.StealAbility();
        Check(stolen != "" && s.activeAbilities.Count == before - 1, "умение украдено");
        s.StartHack(s.gridNodes[0]);
        s.FinishHack(true);
        Check(s.activeAbilities.Count == before, "украденное вернулось после рейда");

        // ── вспомогательный взлом ──
        foreach (var n in s.gridNodes) if (n.zone == 2) { n.infected = true; }
        ServerNode target = null;
        foreach (var n in s.gridNodes) if (n.zone == 2) { target = n; target.infected = false; break; }
        s.StartHack(target);
        Check(s.raid.assist > 0 && s.raid.assistK > 0f, "вспомогательный взлом активен");
        Check(s.raid.trapInterval > GameData.TIERS[target.tier].trapInterval, "ловушки реже с поддержкой");
        Check(s.maxBandwidth >= 150f, "botnet: BW 150+ (и бонус уровня)");
        Check(s.myMaxHp == 4, "УР.2+ даёт +1 HP (3+1)");

        // ── комбо вноса ──
        float g1 = s.DepositValue(10f);
        float g2 = s.DepositValue(10f);
        Check(Math.Abs(g1 - 10f) < 0.01f, "первый внос без множителя");
        Check(Math.Abs(g2 - 11f) < 0.01f && s.ComboCount == 2, "второй внос подряд ×1.1");

        // ── сброс до нуля ──
        s.resetUntil = s.now + 10f;
        Check(s.DisplayClass() == "base", "сброс: скин временно голый");
        s.Tick(11f);
        Check(s.DisplayClass() == "worm", "скин вернулся после сброса");

        // ── дерево: раскладка и клики ──
        var tree = new EvolutionTree();
        tree.Build();
        Check(tree.nodes.Count == 1 + 7 * 10, "созвездие: ядро + 7 веток × 10 узлов");
        int done = 0, locked = 0;
        foreach (var n in tree.nodes)
        {
            var st = tree.NodeState(n);
            if (st == TreeNodeState.Done) done++;
            if (st == TreeNodeState.Locked) locked++;
        }
        Check(done > 5 && locked > 10, "дерево показывает прогресс и запертые спицы");

        // ── кооп-протокол: фреймер и синхронизация ──
        var framer = new NetFramer();
        var packed = NetFramer.Pack("FLAG|door:d_tut");
        var half1 = new byte[3];
        Array.Copy(packed, half1, 3);
        var half2 = new byte[packed.Length - 3];
        Array.Copy(packed, 3, half2, 0, half2.Length);
        var got = framer.Feed(half1, half1.Length);
        Check(got.Count == 0, "фреймер ждёт конца строки");
        got = framer.Feed(half2, half2.Length);
        Check(got.Count == 1 && got[0] == "FLAG|door:d_tut", "фреймер склеил рваные чанки");

        // хост: состояние → снапшот → чистый клиент
        var host = s;   // текущее состояние богатое: флаги/узлы уже есть
        host.SetFlag("lever:s2a");
        host.gridNodes[3].infected = true;
        string snap = NetSync.MsgSnapshot(host);
        var client = new GameState();
        client.NewCampaign();
        NetSync.ApplySnapshot(client, NetSync.Parse(snap));
        Check(client.Flag("lever:s2a"), "снапшот донёс флаг");
        Check(client.gridNodes[3].infected, "снапшот донёс захваченный узел");

        // живые события: флаг и узел применяются без эха
        bool echoed = false;
        client.SendFlag += _ => echoed = true;
        NetSync.ApplyFlag(client, NetSync.Parse(NetSync.MsgFlag("gen:g1")));
        NetSync.ApplyNode(client, NetSync.Parse(NetSync.MsgNode(5)));
        Check(client.Flag("gen:g1") && client.gridNodes[5].infected, "живые FLAG/NODE применились");
        Check(!echoed, "удалённые события не эхуются обратно в сеть");

        // позиция ходит туда-обратно
        var pos = NetSync.Parse(NetSync.MsgPos(2, "raid:7", 1.5f, 0f, -3.25f, 90f));
        Check(pos[0] == "POS" && pos[1] == "2" && pos[2] == "raid:7", "POS кодируется/парсится");

        // ── кооп v2: сид кампании и рейдовые сообщения ──
        // снапшот выравнивает сиды узлов: арены рейдов совпадут с хостом
        Check(client.campaignSeed == host.campaignSeed, "снапшот донёс сид кампании");
        Check(client.gridNodes[7].seed == host.gridNodes[7].seed, "сиды узлов совпали с хостом");
        int keepSeed = client.gridNodes[7].seed;
        client.ReseedCampaign(client.campaignSeed);
        Check(client.gridNodes[7].seed == keepSeed, "повторный перезасев тем же сидом — no-op");

        // состояние системы рейда: тревога/эвакуация/маска вносов/добыча
        var ras = NetSync.Parse(NetSync.MsgRaidState("raid:7", 63.5f, true, 24.5f, false, 0b101, 87.5f));
        Check(ras[0] == "RAS" && ras[1] == "raid:7", "RAS: тип и сцена");
        Check(NetSync.ParseF(ras[2], out var a2) && Math.Abs(a2 - 63.5f) < 0.01f, "RAS: тревога");
        Check(ras[3] == "1" && ras[5] == "0", "RAS: эвакуация открыта, не WIPE");
        Check(int.TryParse(ras[6], out var mask) && mask == 5, "RAS: маска вносов");
        Check(NetSync.ParseF(ras[7], out var acc2) && Math.Abs(acc2 - 87.5f) < 0.01f, "RAS: добыча");

        // роботы/крюки/лут: кодирование → парсинг без потерь
        var rgp = NetSync.Parse(NetSync.MsgGuardPos("raid:7", 2, -10.25f, 4.5f, 180f));
        Check(rgp[0] == "RGP" && rgp[2] == "2" && NetSync.ParseF(rgp[3], out var gx2)
            && Math.Abs(gx2 + 10.25f) < 0.01f, "RGP: позиция робота");
        var rlt = NetSync.Parse(NetSync.MsgLootThrow("raid:7", 3, 1f, 2f, 3f, -4f, 5f, -6f));
        Check(rlt.Length == 9 && rlt[0] == "RLT" && NetSync.ParseF(rlt[8], out var vz2)
            && Math.Abs(vz2 + 6f) < 0.01f, "RLT: бросок с вектором скорости");
        var rlc = NetSync.Parse(NetSync.MsgLootCarry("raid:7", 4, 2));
        Check(rlc[0] == "RLC" && rlc[2] == "4" && rlc[3] == "2", "RLC: захват лута");
        var rald = NetSync.Parse(NetSync.MsgAlarmDelta("raid:7", -8f));
        Check(rald[0] == "RALD" && NetSync.ParseF(rald[2], out var d2)
            && Math.Abs(d2 + 8f) < 0.01f, "RALD: поправка тревоги");
        var rhc = NetSync.Parse(NetSync.MsgHookCaught("raid:7", 1));
        Check(rhc[0] == "RHC" && rhc[2] == "1", "RHC: зацеп крюком");

        // ── сохранение: сериализация → чистое состояние → загрузка ──
        s.SetFlag("door:d_tut");
        s.SetFlag("mote:5");                     // подобранный мот — одноразовый
        s.gridNodes[7].infected = true;
        s.gridNodes[2].failed = true;
        s.currentNode = s.gridNodes[7];          // точка возврата в Грид
        s.resources["data_fragments"] = 123;
        s.blockPositions[2] = new UnityEngine.Vector3(1.5f, 0f, -3.25f);
        string save = s.Serialize();
        var restored = new GameState();
        Check(restored.Deserialize(save), "сейв распознан");
        Check(restored.branch == s.branch && restored.virusLevel == s.virusLevel, "ветка и уровень восстановлены");
        Check(restored.activeAbilities.Count == s.activeAbilities.Count, "активки восстановлены");
        Check(restored.Flag("door:d_tut") && restored.gridNodes[7].infected, "флаги и захваты восстановлены");
        Check(restored.resources["data_fragments"] == 123, "ресурсы восстановлены");
        Check(restored.career["deposits"] == s.career["deposits"], "карьера восстановлена");
        Check(Math.Abs(restored.blockPositions[2].z - (-3.25f)) < 0.01f, "позиции блоков восстановлены");
        Check(!restored.Deserialize("мусор"), "битый сейв отвергнут");
        // чекпойнт и арены: сид кампании, точка возврата, проваленные, моты
        Check(restored.campaignSeed == s.campaignSeed, "сейв: сид кампании");
        Check(restored.gridNodes[7].seed == s.gridNodes[7].seed, "сейв: сиды узлов (те же арены)");
        Check(restored.currentNode != null && restored.currentNode.id == 7, "сейв: спавн у последнего узла");
        Check(restored.gridNodes[2].failed, "сейв: проваленные узлы");
        Check(restored.Flag("mote:5"), "сейв: мот не возродится");

        // ── архетипы серверов: правило узла из сида, детерминированно ──
        foreach (var n in s.gridNodes)
        {
            if (n.zone == 0)
                Check(n.arch == "", $"обучение без архетипов (узел {n.id})");
            else if (n.arch != "")
            {
                Check(GameData.ARCHETYPES.ContainsKey(n.arch), $"архетип узла {n.id} известен");
                Check(n.tier >= GameData.ARCHETYPES[n.arch].minTier, $"архетип узла {n.id} по тиру");
                Check(n.arch == GameData.ArchForNode(n.seed, n.zone, n.tier), $"архетип узла {n.id} из сида");
            }
        }
        {
            // ресид по чужому сиду (кооп-клиент) даёт те же архетипы, что у хоста
            var archHost = new GameState(); archHost.NewCampaign();
            var archClient = new GameState(); archClient.NewCampaign();
            archClient.ReseedCampaign(archHost.campaignSeed);
            bool archMatch = true, anyArch = false;
            for (int i = 0; i < archHost.gridNodes.Count; i++)
            {
                if (archHost.gridNodes[i].arch != archClient.gridNodes[i].arch) archMatch = false;
                if (archHost.gridNodes[i].arch != "") anyArch = true;
            }
            Check(archMatch, "кооп: архетипы совпадают после ресида");
            Check(anyArch, "хотя бы один узел с архетипом");
            // архетип попадает в конфиг рейда; карантин лаборатории ужимает числа
            var probe = new GameState(); probe.NewCampaign();
            ServerNode avNode = null;
            foreach (var n in probe.gridNodes) if (n.arch == "avlab") { avNode = n; break; }
            if (avNode != null)
            {
                var baseTier = GameData.TIERS[avNode.tier];
                probe.StartHack(avNode);
                Check(probe.raid.arch == "avlab", "архетип в конфиге рейда");
                Check(probe.raid.trapInterval > baseTier.trapInterval, "карантин: ловушки реже");
                Check(probe.raid.camRange > baseTier.camRange, "карантин: датчики зорче");
            }
        }

        // ── кооп-скейлинг: стая из 4 делает рейд жирнее и злее ──
        var t0 = GameData.TIERS[0];
        s.packSize = 4;
        s.StartHack(s.gridNodes[0]);
        Check(s.raid.quota == (int)(t0.quota * (1f + 0.4f * 3)), "стая 4: квота +120%");
        Check(s.raid.files == t0.files + 3 && s.raid.crates == t0.crates + 1, "стая 4: больше лута");
        Check(s.raid.creep > t0.creep, "стая 4: тревога живее");
        Check(s.raid.safes == 0, "тир 0: без сейфов");
        ServerNode tier2 = null;
        foreach (var n in s.gridNodes) if (n.tier == 2 && !n.infected) { tier2 = n; break; }
        s.StartHack(tier2);
        Check(s.raid.safes >= 1, "тир 2: сейф на месте");
        Check(s.raid.hot >= 1, "тир 2: горячий пакет в хранилище");
        Check(s.raid.sensitivity == Math.Min(GameData.TIERS[2].sensitivity + 1, 4), "стая 4: больше роботов");
        s.packSize = 1;
        s.StartHack(s.gridNodes[0]);
        Check(s.raid.quota == t0.quota && s.raid.files == t0.files, "соло: базовый рейд без множителей");

        // ── адаптивный АВ: учится на заезженном приёме, T0 не контрит ──
        s.avSeen["dunk"] = GameState.AV_LEARN_AT;
        s.StartHack(tier2);
        Check(s.avCounter == "dunk", "АВ выучил данки на пороге");
        Check(s.avSeen["dunk"] == 0, "счётчик приёма сброшен после обучения");
        Check(GameState.AV_COUNTER_DESC.ContainsKey("dunk"), "у контрмеры есть описание");
        s.StartHack(tier2);
        Check(s.avCounter == "", "без злоупотреблений контрмеры нет");
        s.avSeen["jam"] = GameState.AV_LEARN_AT + 2;
        s.StartHack(s.gridNodes[0]);
        Check(s.avCounter == "", "обучение T0: АВ не адаптируется");
        Check(s.avSeen["jam"] == GameState.AV_LEARN_AT + 2, "T0 не тратит накопленное обучение");
        s.avSeen["morph"] = 3;
        var avRestored = new GameState();
        avRestored.Deserialize(s.Serialize());
        Check(avRestored.avSeen["morph"] == 3 && avRestored.avSeen["jam"] == s.avSeen["jam"],
            "обучение АВ переживает сейв");
        s.avSeen["jam"] = 0; s.avSeen["morph"] = 0;

        // рекорды: данк/комбо/лучшая добыча копятся и сериализуются
        s.StartHack(s.gridNodes[1]);
        s.lastDunks = 2;
        s.DepositValue(30f);
        s.DepositValue(30f);
        s.FinishHack(true);
        Check(s.records["dunks"] >= 2 && s.records["bestCombo"] >= 2 && s.records["bestLoot"] >= 60, "рекорды обновлены");
        Check(s.lastRecordLoot, "флаг нового рекорда добычи");
        var restored2 = new GameState();
        restored2.Deserialize(s.Serialize());
        Check(restored2.records["bestCombo"] == s.records["bestCombo"], "рекорды в сейве");

        Console.WriteLine(_fails == 0
            ? "SELFTEST OK — все проверки ядра прошли"
            : $"SELFTEST: {_fails} провалов");
        return _fails == 0 ? 0 : 1;
    }
}
