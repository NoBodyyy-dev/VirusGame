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

        Console.WriteLine(_fails == 0
            ? "SELFTEST OK — все проверки ядра прошли"
            : $"SELFTEST: {_fails} провалов");
        return _fails == 0 ? 0 : 1;
    }
}
