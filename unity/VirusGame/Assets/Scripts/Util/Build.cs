using UnityEngine;
using TMPro;

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

        public static TextMeshPro Label(Transform parent, string text, Vector3 pos, float size,
                                        Color color, bool billboard = true)
        {
            var go = new GameObject("label");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            var t = go.AddComponent<TextMeshPro>();
            t.text = text;
            t.fontSize = size;
            t.color = color;
            t.alignment = TextAlignmentOptions.Center;
            t.rectTransform.sizeDelta = new Vector2(20, 4);
            if (billboard) go.AddComponent<Billboard>();
            return t;
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
