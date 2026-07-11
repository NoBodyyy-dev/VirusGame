using UnityEngine;

namespace Virus.Util
{
    // Порт билд-хелперов grid_world.gd (_mesh_box/_collide/_solid/_label3d/_omni/
    // _spot_down). В Godot всё строилось процедурно через add_child — в Unity это
    // GameObject + компоненты. Общий куб-меш кэшируется.
    public static class Build
    {
        static Mesh _cube;
        static Mesh Cube
        {
            get
            {
                if (_cube == null)
                {
                    var tmp = GameObject.CreatePrimitive(PrimitiveType.Cube);
                    _cube = tmp.GetComponent<MeshFilter>().sharedMesh;
                    Object.Destroy(tmp);
                }
                return _cube;
            }
        }

        public static GameObject MeshBox(Transform parent, Vector3 size, Material mat, Vector3 pos)
        {
            var go = new GameObject("box");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localScale = size;
            go.AddComponent<MeshFilter>().sharedMesh = Cube;
            go.AddComponent<MeshRenderer>().sharedMaterial = mat;
            return go;
        }

        public static GameObject Collide(Transform parent, Vector3 size, Vector3 pos)
        {
            var go = new GameObject("collider") { isStatic = true };
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            var bc = go.AddComponent<BoxCollider>();
            bc.size = size;
            return go;
        }

        public static void Solid(Transform parent, Vector3 size, Material mat, Vector3 pos)
        {
            MeshBox(parent, size, mat, pos);
            Collide(parent, size, pos);
        }

        // Примитив (сфера/цилиндр/капсула…) — против «всё квадратное».
        // collide=true оставляет родной коллайдер примитива (Sphere/Capsule/Mesh).
        public static GameObject Prim(PrimitiveType t, Transform parent, Vector3 scale, Material mat,
                                      Vector3 pos, bool collide = false)
        {
            var go = GameObject.CreatePrimitive(t);
            if (!collide) Object.Destroy(go.GetComponent<Collider>());
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localScale = scale;
            go.GetComponent<MeshRenderer>().sharedMaterial = mat;
            return go;
        }

        // Шрифт ОС в рантайме — не требует импортированных TMP-ассетов, работает
        // и в сборке. Шейдер "GUI/Text Shader" включаем в билд (см. UnityBuild).
        static Font _font;
        public static Font UIFont
        {
            get
            {
                if (_font == null)
                {
                    _font = Font.CreateDynamicFontFromOSFont("Arial", 40)
                         ?? Font.CreateDynamicFontFromOSFont(
                                new[] { "Segoe UI", "Tahoma", "Verdana", "Liberation Sans" }, 40);
                }
                return _font;
            }
        }

        // Материал текста с честным ZTest: не просвечивает сквозь стены
        // (встроенный GUI/Text Shader рисует поверх всей геометрии).
        static Material _worldTextMat;
        static Material WorldTextMat
        {
            get
            {
                if (_worldTextMat == null)
                {
                    var sh = Shader.Find("Virus/WorldText");
                    if (sh != null && UIFont != null) _worldTextMat = new Material(sh);
                }
                if (_worldTextMat != null && UIFont != null)
                    _worldTextMat.mainTexture = UIFont.material.mainTexture;   // атлас мог перестроиться
                return _worldTextMat;
            }
        }

        // 3D-метка в мире (порт Label3D) на legacy TextMesh.
        public static TextMesh Label(Transform parent, string text, Vector3 pos, float size,
                                     Color color, bool billboard = true)
        {
            var go = new GameObject("label");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            var tm = go.AddComponent<TextMesh>();
            tm.font = UIFont;
            tm.text = text;
            tm.fontSize = 40;
            tm.characterSize = size * 0.08f;    // перевод «размера шрифта» в масштаб мира
            tm.anchor = TextAnchor.MiddleCenter;
            tm.alignment = TextAlignment.Center;
            tm.color = color;
            var mr = go.GetComponent<MeshRenderer>();
            if (mr != null && UIFont != null) mr.sharedMaterial = WorldTextMat != null ? WorldTextMat : UIFont.material;
            if (billboard) go.AddComponent<Billboard>();
            return tm;
        }

        public static Light Omni(Transform parent, Vector3 pos, Color color, float energy, float range)
        {
            var go = new GameObject("omni");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            var l = go.AddComponent<Light>();
            l.type = LightType.Point;
            l.color = color;
            l.intensity = energy;
            l.range = range;
            l.shadows = LightShadows.None;
            return l;
        }

        public static Light SpotDown(Transform parent, Vector3 pos, Color color, float energy, float range, float angle = 55f)
        {
            var go = new GameObject("spot");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = Quaternion.Euler(90, 0, 0);
            var l = go.AddComponent<Light>();
            l.type = LightType.Spot;
            l.color = color;
            l.intensity = energy;
            l.range = range;
            l.spotAngle = angle;
            l.shadows = LightShadows.None;
            return l;
        }
    }

    // Godot Label3D billboard=BILLBOARD_ENABLED → простой билборд к камере.
    public class Billboard : MonoBehaviour
    {
        void LateUpdate()
        {
            var cam = Camera.main;
            if (cam == null) return;
            transform.rotation = Quaternion.LookRotation(transform.position - cam.transform.position);
        }
    }
}
