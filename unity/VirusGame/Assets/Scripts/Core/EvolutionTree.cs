using System.Collections.Generic;
using UnityEngine;

namespace Virus.Core
{
    // Порт модели evolution_ui.gd: раскладка узлов-созвездия, состояния,
    // семантика клика и тексты тултипов. Чистая логика без движка —
    // отрисовкой занимается UI/EvolutionUI (Unity-слой).
    public enum TreeNodeKind { Core, Level, Branch, Ability, Secondary }
    public enum TreeNodeState { Locked, Open, Done, Task, Hint }
    public enum TreeClickResult { None, Upgraded, Unequipped, Denied }

    public class TreeNode
    {
        public int id, lvl, slot, link;
        public TreeNodeKind kind;
        public string cls = "", ability = "";
        public Vector2 pos;
        public float r;
    }

    public class EvolutionTree
    {
        public readonly List<TreeNode> nodes = new();
        GameState S => GameState.I;

        static readonly string[] BranchOrder = GameData.BRANCHES;

        // позиции в «мировых» координатах дерева (до зума), центр = (0,0)
        public void Build()
        {
            nodes.Clear();
            nodes.Add(new TreeNode { id = 0, kind = TreeNodeKind.Core, pos = new Vector2(0, 0), r = 34f, link = -1 });
            int nid = 1, count = BranchOrder.Length;
            for (int i = 0; i < count; i++)
            {
                string cls = BranchOrder[i];
                float ang = Mathf.PI * 2f * i / count - Mathf.PI * 0.5f;
                var dir = new Vector2(Mathf.Cos(ang), Mathf.Sin(ang));
                // УР.1 → ворота ветки → УР.2 → активки → УР.3 → финальные активки
                int lvl1 = nid;
                nodes.Add(new TreeNode { id = nid++, kind = TreeNodeKind.Level, lvl = 1, cls = cls, pos = dir * 105f, r = 13f, link = 0 });
                int gate = nid;
                nodes.Add(new TreeNode { id = nid++, kind = TreeNodeKind.Branch, cls = cls, pos = dir * 175f, r = 26f, link = lvl1 });
                int lvl2 = nid;
                nodes.Add(new TreeNode { id = nid++, kind = TreeNodeKind.Level, lvl = 2, cls = cls, pos = dir * 245f, r = 13f, link = gate });
                // пять умений ветки: 3 веером от УР.2, ещё 2 — за УР.3
                var pool = GameData.BRANCH_ABILITIES[cls];
                float[] fan = { -0.22f, 0f, 0.22f };
                var abIds = new int[3];
                for (int k = 0; k < 3; k++)
                {
                    float a2 = ang + fan[k];
                    var d2 = new Vector2(Mathf.Cos(a2), Mathf.Sin(a2));
                    float rr = k != 1 ? 305f : 328f;
                    abIds[k] = nid;
                    nodes.Add(new TreeNode { id = nid++, kind = TreeNodeKind.Ability, cls = cls, ability = pool[k],
                        slot = k, pos = d2 * rr, r = k == 0 ? 17f : 15f, link = lvl2 });
                }
                int lvl3 = nid;
                nodes.Add(new TreeNode { id = nid++, kind = TreeNodeKind.Level, lvl = 3, cls = cls, pos = dir * 398f, r = 13f, link = abIds[1] });
                for (int k2 = 0; k2 < 2; k2++)
                {
                    float a3 = ang + (k2 == 0 ? -0.17f : 0.17f);
                    nodes.Add(new TreeNode { id = nid++, kind = TreeNodeKind.Ability, cls = cls, ability = pool[3 + k2],
                        slot = 3 + k2, pos = new Vector2(Mathf.Cos(a3), Mathf.Sin(a3)) * 448f, r = 15f, link = lvl3 });
                }
                // узел доп. ветки (виден на УР.3)
                nodes.Add(new TreeNode { id = nid++, kind = TreeNodeKind.Secondary, cls = cls, pos = dir * 498f, r = 15f, link = lvl3 });
            }
        }

        public bool MyBranchActive(string cls) => S.branch == cls || S.secondaryBranch == cls;

        // ── состояние узла: locked / open (можно взять) / done / task / hint ──
        public TreeNodeState NodeState(TreeNode n)
        {
            switch (n.kind)
            {
                case TreeNodeKind.Core:
                    return TreeNodeState.Done;
                case TreeNodeKind.Level:
                    if (S.branch == n.cls && S.virusLevel >= n.lvl) return TreeNodeState.Done;
                    if (S.branch == n.cls && S.virusLevel == n.lvl - 1 && S.CanLevelUp()) return TreeNodeState.Open;
                    if (S.branch == "" && n.lvl == 1) return TreeNodeState.Hint;   // сначала ветка
                    return TreeNodeState.Locked;
                case TreeNodeKind.Branch:
                    if (MyBranchActive(n.cls)) return TreeNodeState.Done;
                    if (S.branch == "") return TreeNodeState.Open;
                    if (S.virusLevel >= 3 && S.secondaryBranch == "") return TreeNodeState.Open;   // доп. ветка
                    return TreeNodeState.Locked;
                case TreeNodeKind.Ability:
                    if (S.activeAbilities.Contains(n.ability)) return TreeNodeState.Done;
                    if (S.CanPickAbility(n.ability)) return TreeNodeState.Open;
                    if ((n.cls == S.branch || n.cls == S.secondaryBranch) && S.AbilityPool().Contains(n.ability))
                        return TreeNodeState.Task;   // видна, но заперта заданием/уровнем
                    return TreeNodeState.Locked;
                case TreeNodeKind.Secondary:
                    if (S.secondaryBranch == n.cls) return TreeNodeState.Done;
                    if (S.virusLevel >= 3 && S.secondaryBranch == "" && n.cls != S.branch) return TreeNodeState.Open;
                    return TreeNodeState.Locked;
            }
            return TreeNodeState.Locked;
        }

        public Color NodeColor(TreeNode n, TreeNodeState state)
        {
            var clsCol = GameData.CLASSES.TryGetValue(n.cls == "" ? "base" : n.cls, out var ci)
                ? ci.color : new Color(0.85f, 0.62f, 0.3f);
            return state switch
            {
                TreeNodeState.Done => (n.kind == TreeNodeKind.Level || n.kind == TreeNodeKind.Core)
                    ? new Color(1f, 0.85f, 0.5f) : clsCol,
                TreeNodeState.Open => new Color(0.85f, 0.62f, 0.3f),
                TreeNodeState.Task => new Color(0.55f, 0.45f, 0.3f),
                TreeNodeState.Hint => new Color(0.5f, 0.42f, 0.28f),
                _ => new Color(0.16f, 0.15f, 0.17f),
            };
        }

        public string Glyph(TreeNode n) => n.kind switch
        {
            TreeNodeKind.Core => "◉",
            TreeNodeKind.Level => n.lvl.ToString(),
            TreeNodeKind.Branch => GameData.CLASSES[n.cls].name.Substring(0, 1),
            TreeNodeKind.Ability => GameData.ABILITIES[n.ability].name.Substring(0, 1),
            _ => "+",
        };

        // ── клик: прокачка или откат ──
        public TreeClickResult Click(TreeNode n)
        {
            var st = NodeState(n);
            // откат: клик по экипированному умению снимает его
            if (st == TreeNodeState.Done && n.kind == TreeNodeKind.Ability)
                return S.UnequipAbility(n.ability) ? TreeClickResult.Unequipped : TreeClickResult.None;
            if (st != TreeNodeState.Open) return TreeClickResult.Denied;
            bool ok = n.kind switch
            {
                TreeNodeKind.Level => S.LevelUp(),
                TreeNodeKind.Branch => S.branch == "" ? S.ChooseBranch(n.cls) : S.ChooseSecondary(n.cls),
                TreeNodeKind.Ability => S.PickAbility(n.ability),
                TreeNodeKind.Secondary => S.ChooseSecondary(n.cls),
                _ => false,
            };
            return ok ? TreeClickResult.Upgraded : TreeClickResult.Denied;
        }

        // ── тултип ──
        public string TooltipTitle(TreeNode n) => n.kind switch
        {
            TreeNodeKind.Core => "ПРОТО-ШТАММ",
            TreeNodeKind.Level => GameData.LEVELS[n.lvl].title,
            TreeNodeKind.Branch => $"{GameData.CLASSES[n.cls].name} — {GameData.CLASSES[n.cls].role}",
            TreeNodeKind.Ability => GameData.ABILITIES[n.ability].name,
            _ => $"ДОП. ВЕТКА: {GameData.CLASSES[n.cls].name}",
        };

        public List<string> TooltipLines(TreeNode n)
        {
            var st = NodeState(n);
            var lines = new List<string>();
            switch (n.kind)
            {
                case TreeNodeKind.Core:
                    lines.Add("исходная форма — с этого начинают все");
                    break;
                case TreeNodeKind.Level:
                    lines.Add(GameData.LEVELS[n.lvl].perks);
                    if (st == TreeNodeState.Open) lines.Add($"КЛИК: эволюция за {CostText(S.LevelCost(n.lvl))}");
                    else if (st == TreeNodeState.Hint) lines.Add("сначала выбери ветку (большой узел)");
                    else if (st == TreeNodeState.Locked && S.branch != "" && n.cls != S.branch)
                        lines.Add("это спица другой ветки");
                    break;
                case TreeNodeKind.Branch:
                    lines.Add(GameData.CLASSES[n.cls].passive);
                    if (S.branch == "") lines.Add("КЛИК: выбрать направленность (только одна!)");
                    else if (st == TreeNodeState.Open) lines.Add("КЛИК: взять ДОП. ВЕТКОЙ (УР.3)");
                    break;
                case TreeNodeKind.Ability:
                    lines.Add(GameData.ABILITIES[n.ability].desc);
                    lines.Add($"расход: {(int)S.AbilityCost(n.ability)} BW");
                    int depth = S.AbilityDepth(n.ability);
                    if (st == TreeNodeState.Done)
                        lines.Add("КЛИК: снять умение (откат бесплатный, слот освободится)");
                    else if (st == TreeNodeState.Open)
                        lines.Add($"КЛИК: экипировать в слот {S.activeAbilities.Count + 1}");
                    else if (st == TreeNodeState.Task)
                    {
                        if (!S.AbilityTaskDone(depth)) lines.Add($"ЗАДАНИЕ: {S.AbilityTaskProgress(depth)}");
                        else if (S.activeAbilities.Count >= S.MaxAbilitySlots())
                            lines.Add("слоты заняты — сними другое умение или подними уровень");
                        else lines.Add("нужен уровень штамма выше");
                    }
                    break;
                case TreeNodeKind.Secondary:
                    lines.Add("элементы её скина и умения добавятся к текущим");
                    if (st == TreeNodeState.Open) lines.Add("КЛИК: взять вторую направленность");
                    else if (S.virusLevel < 3) lines.Add("откроется на УР.3");
                    break;
            }
            return lines;
        }

        public static string CostText(Dictionary<string, int> cost)
        {
            var icons = new Dictionary<string, string>
                { ["data_fragments"] = "◈", ["code_samples"] = "◇", ["mutagen"] = "✦" };
            var parts = new List<string>();
            foreach (var kv in cost)
                parts.Add($"{icons.GetValueOrDefault(kv.Key, kv.Key)} {kv.Value}");
            return parts.Count > 0 ? string.Join(" · ", parts) : "бесплатно";
        }
    }
}
