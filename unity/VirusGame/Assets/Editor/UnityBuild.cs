using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.SceneManagement;

namespace Virus.EditorTools
{
    // Шейдеры, не использованные ни одним ассетом, вырезаются из билда, и тогда
    // Shader.Find(...) в плеере возвращает null. Материалы Mats создаются в
    // рантайме через Shader.Find("Standard") — поэтому шейдер надо принудительно
    // включить в сборку (Graphics → Always Included Shaders).
    // Автосборка без GUI (вызывается через -executeMethod в batchmode):
    // создаёт сцену GridWorld с бутстрапом, кладёт в Build Settings и собирает
    // Standalone-плеер. Рендер — встроенный конвейер (URP-ассет не назначаем,
    // материалы Mats работают и там, и там).
    public static class UnityBuild
    {
        static void MakeScene(string name, System.Type bootType)
        {
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            new GameObject("Boot", bootType);
            EditorSceneManager.SaveScene(scene, $"Assets/Scenes/{name}.unity");
        }

        [MenuItem("Virus/Setup Scene")]
        public static void SetupScene()
        {
            Directory.CreateDirectory("Assets/Scenes");
            MakeScene("MainMenu", typeof(Virus.App.MenuBoot));
            MakeScene("GridWorld", typeof(Virus.App.Boot));
            MakeScene("Level", typeof(Virus.App.LevelBoot));
            MakeScene("VictoryTunnel", typeof(Virus.App.VictoryBoot));
            EditorBuildSettings.scenes = new[]
            {
                new EditorBuildSettingsScene("Assets/Scenes/MainMenu.unity", true),
                new EditorBuildSettingsScene("Assets/Scenes/GridWorld.unity", true),
                new EditorBuildSettingsScene("Assets/Scenes/Level.unity", true),
                new EditorBuildSettingsScene("Assets/Scenes/VictoryTunnel.unity", true),
            };
            AssetDatabase.SaveAssets();
            Debug.Log("[VirusBuild] scenes ready");
        }

        static void EnsureShaderIncluded(string shaderName)
        {
            var shader = Shader.Find(shaderName);
            if (shader == null) { Debug.LogWarning($"[VirusBuild] shader '{shaderName}' not found"); return; }
            var gsPath = "ProjectSettings/GraphicsSettings.asset";
            var gsObj = AssetDatabase.LoadAllAssetsAtPath(gsPath)[0];
            var so = new SerializedObject(gsObj);
            var arr = so.FindProperty("m_AlwaysIncludedShaders");
            for (int i = 0; i < arr.arraySize; i++)
                if (arr.GetArrayElementAtIndex(i).objectReferenceValue == shader) return; // уже есть
            arr.InsertArrayElementAtIndex(arr.arraySize);
            arr.GetArrayElementAtIndex(arr.arraySize - 1).objectReferenceValue = shader;
            so.ApplyModifiedProperties();
            Debug.Log($"[VirusBuild] +always-included shader '{shaderName}'");
        }

        // Импорт TMP Essentials (шрифт по умолчанию) без GUI. API у importer'а
        // менялся между версиями — зовём через рефлексию, ошибку глотаем.
        static void EnsureTMPEssentials()
        {
            if (Directory.Exists("Assets/TextMesh Pro/Resources")) return;
            try
            {
                var t = System.Type.GetType("TMPro.TMP_PackageResourceImporter, Unity.TextMeshPro.Editor")
                     ?? System.Type.GetType("TMPro.TMP_PackageResourceImporter, Unity.TextMeshPro");
                if (t == null) { Debug.LogWarning("[VirusBuild] TMP importer not found — текст будет без шрифта"); return; }
                var mi = t.GetMethod("ImportResources");
                object inst = (mi != null && mi.IsStatic) ? null : System.Activator.CreateInstance(t);
                mi?.Invoke(inst, new object[] { true, false, false });
                AssetDatabase.Refresh();
                Debug.Log("[VirusBuild] TMP essentials imported");
            }
            catch (System.Exception e) { Debug.LogWarning("[VirusBuild] TMP import skipped: " + e.Message); }
        }

        // Убрать DontSave-шейдеры из always-included (иначе билд падает).
        static void RemoveShaderIncluded(string shaderName)
        {
            var gsObj = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/GraphicsSettings.asset")[0];
            var so = new SerializedObject(gsObj);
            var arr = so.FindProperty("m_AlwaysIncludedShaders");
            bool changed = false;
            for (int i = arr.arraySize - 1; i >= 0; i--)
            {
                var sh = arr.GetArrayElementAtIndex(i).objectReferenceValue as Shader;
                if (sh == null || sh.name == shaderName)
                {
                    arr.DeleteArrayElementAtIndex(i);
                    changed = true;
                }
            }
            if (changed) { so.ApplyModifiedProperties(); Debug.Log($"[VirusBuild] -always-included '{shaderName}'/null"); }
        }

        // ── URP: пайплайн-ассет (Forward+), HDR, базовые материалы в Resources.
        // Материалы-ассеты тянут в билд шейдер URP/Lit ровно с нужными
        // вариантами (always-included для URP/Lit взорвал бы время сборки).
        [MenuItem("Virus/Setup URP")]
        public static void SetupURP()
        {
            Directory.CreateDirectory("Assets/Settings");
            Directory.CreateDirectory("Assets/Resources");

            var rendererData = AssetDatabase.LoadAssetAtPath<UniversalRendererData>("Assets/Settings/URPRenderer.asset");
            if (rendererData == null)
            {
                rendererData = ScriptableObject.CreateInstance<UniversalRendererData>();
                rendererData.renderingMode = RenderingMode.ForwardPlus;   // много точечных огней
                AssetDatabase.CreateAsset(rendererData, "Assets/Settings/URPRenderer.asset");
            }
            var rp = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>("Assets/Settings/URPAsset.asset");
            if (rp == null)
            {
                rp = UniversalRenderPipelineAsset.Create(rendererData);
                AssetDatabase.CreateAsset(rp, "Assets/Settings/URPAsset.asset");
            }
            rp.supportsHDR = true;
            rp.msaaSampleCount = 4;
            rp.shadowDistance = 70f;
            GraphicsSettings.defaultRenderPipeline = rp;
            QualitySettings.renderPipeline = rp;

            var lit = Shader.Find("Universal Render Pipeline/Lit");
            if (lit != null)
            {
                if (AssetDatabase.LoadAssetAtPath<Material>("Assets/Resources/mat_urp_lit.mat") == null)
                    AssetDatabase.CreateAsset(new Material(lit), "Assets/Resources/mat_urp_lit.mat");
                if (AssetDatabase.LoadAssetAtPath<Material>("Assets/Resources/mat_urp_lit_emissive.mat") == null)
                {
                    var em = new Material(lit);
                    em.EnableKeyword("_EMISSION");
                    em.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
                    em.SetColor("_EmissionColor", Color.white);
                    AssetDatabase.CreateAsset(em, "Assets/Resources/mat_urp_lit_emissive.mat");
                }
            }
            AssetDatabase.SaveAssets();
            Debug.Log("[VirusBuild] URP configured (Forward+, HDR, base mats)");
        }

        [MenuItem("Virus/Build Windows")]
        public static void BuildWindows()
        {
            PlayerSettings.runInBackground = true;   // кооп двумя окнами + автопроверки
            SetupURP();
            // Форсим только Standard (обычный шейдер, иначе вырезается).
            // Шрифтовые/UI-шейдеры (GUI/Text Shader, UI/Default) — встроенные
            // DontSave-ресурсы, Unity кладёт их в билд сам; форсить их нельзя.
            RemoveShaderIncluded("GUI/Text Shader");
            EnsureShaderIncluded("Standard");
            EnsureShaderIncluded("Skybox/Procedural");   // ночное небо (Shader.Find в рантайме)
            SetupScene();
            var dir = Path.GetFullPath("../Build");
            Directory.CreateDirectory(dir);
            var opts = new BuildPlayerOptions
            {
                scenes = new[]
                {
                    "Assets/Scenes/MainMenu.unity",
                    "Assets/Scenes/GridWorld.unity",
                    "Assets/Scenes/Level.unity",
                    "Assets/Scenes/VictoryTunnel.unity",
                },
                locationPathName = Path.Combine(dir, "VirusUnity.exe"),
                target = BuildTarget.StandaloneWindows64,
                options = BuildOptions.None,
            };
            var report = BuildPipeline.BuildPlayer(opts);
            Debug.Log($"[VirusBuild] result={report.summary.result} " +
                      $"errors={report.summary.totalErrors} size={report.summary.totalSize}");
            if (report.summary.result != UnityEditor.Build.Reporting.BuildResult.Succeeded)
                EditorApplication.Exit(1);
        }
    }
}
