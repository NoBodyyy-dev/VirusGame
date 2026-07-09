using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
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
        [MenuItem("Virus/Setup Scene")]
        public static void SetupScene()
        {
            Directory.CreateDirectory("Assets/Scenes");
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            new GameObject("Boot", typeof(Virus.App.Boot));
            EditorSceneManager.SaveScene(scene, "Assets/Scenes/GridWorld.unity");
            EditorBuildSettings.scenes = new[]
            {
                new EditorBuildSettingsScene("Assets/Scenes/GridWorld.unity", true),
            };
            AssetDatabase.SaveAssets();
            Debug.Log("[VirusBuild] scene ready");
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

        [MenuItem("Virus/Build Windows")]
        public static void BuildWindows()
        {
            // Форсим только Standard (обычный шейдер, иначе вырезается).
            // Шрифтовые/UI-шейдеры (GUI/Text Shader, UI/Default) — встроенные
            // DontSave-ресурсы, Unity кладёт их в билд сам; форсить их нельзя.
            RemoveShaderIncluded("GUI/Text Shader");
            EnsureShaderIncluded("Standard");
            SetupScene();
            var dir = Path.GetFullPath("../Build");
            Directory.CreateDirectory(dir);
            var opts = new BuildPlayerOptions
            {
                scenes = new[] { "Assets/Scenes/GridWorld.unity" },
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
