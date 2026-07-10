// РАСШИРЕННЫЕ заглушки UnityEngine — ТОЛЬКО для offline-проверки компиляции
// ВСЕГО Unity-слоя (Assets/Scripts без Editor) через dotnet, когда сам Unity
// недоступен. Поведение не эмулируется — важны только сигнатуры типов.
// В Unity этот файл не используется.
using System;
using System.Collections;
using System.Collections.Generic;

namespace UnityEngine
{
    // ── математика ──
    public struct Vector2
    {
        public float x, y;
        public Vector2(float x, float y) { this.x = x; this.y = y; }
        public static Vector2 zero => new(0, 0);
        public static Vector2 one => new(1, 1);
        public float magnitude => (float)Math.Sqrt(x * x + y * y);
        public float sqrMagnitude => x * x + y * y;
        public Vector2 normalized { get { var m = magnitude; return m > 1e-6f ? new Vector2(x / m, y / m) : zero; } }
        public static Vector2 operator +(Vector2 a, Vector2 b) => new(a.x + b.x, a.y + b.y);
        public static Vector2 operator -(Vector2 a, Vector2 b) => new(a.x - b.x, a.y - b.y);
        public static Vector2 operator *(Vector2 v, float k) => new(v.x * k, v.y * k);
        public static Vector2 operator *(float k, Vector2 v) => new(v.x * k, v.y * k);
        public static Vector2 operator /(Vector2 v, float k) => new(v.x / k, v.y / k);
        public static bool operator ==(Vector2 a, Vector2 b) => a.x == b.x && a.y == b.y;
        public static bool operator !=(Vector2 a, Vector2 b) => !(a == b);
        public override bool Equals(object o) => o is Vector2 v && v == this;
        public override int GetHashCode() => x.GetHashCode() ^ y.GetHashCode();
        public static float Distance(Vector2 a, Vector2 b) => (a - b).magnitude;
        public static Vector2 Lerp(Vector2 a, Vector2 b, float t) => a + (b - a) * Mathf.Clamp01(t);
        public static implicit operator Vector3(Vector2 v) => new(v.x, v.y, 0);
    }

    public struct Vector3
    {
        public float x, y, z;
        public Vector3(float x, float y, float z) { this.x = x; this.y = y; this.z = z; }
        public Vector3(float x, float y) { this.x = x; this.y = y; z = 0; }
        public static Vector3 zero => new(0, 0, 0);
        public static Vector3 one => new(1, 1, 1);
        public static Vector3 up => new(0, 1, 0);
        public static Vector3 down => new(0, -1, 0);
        public static Vector3 left => new(-1, 0, 0);
        public static Vector3 right => new(1, 0, 0);
        public static Vector3 forward => new(0, 0, 1);
        public static Vector3 back => new(0, 0, -1);
        public float magnitude => (float)Math.Sqrt(x * x + y * y + z * z);
        public float sqrMagnitude => x * x + y * y + z * z;
        public Vector3 normalized { get { var m = magnitude; return m > 1e-6f ? this / m : zero; } }
        public void Normalize() { var n = normalized; x = n.x; y = n.y; z = n.z; }
        public static Vector3 operator +(Vector3 a, Vector3 b) => new(a.x + b.x, a.y + b.y, a.z + b.z);
        public static Vector3 operator -(Vector3 a, Vector3 b) => new(a.x - b.x, a.y - b.y, a.z - b.z);
        public static Vector3 operator -(Vector3 a) => new(-a.x, -a.y, -a.z);
        public static Vector3 operator *(Vector3 v, float k) => new(v.x * k, v.y * k, v.z * k);
        public static Vector3 operator *(float k, Vector3 v) => v * k;
        public static Vector3 operator /(Vector3 v, float k) => new(v.x / k, v.y / k, v.z / k);
        public static float Distance(Vector3 a, Vector3 b) => (a - b).magnitude;
        public static Vector3 Lerp(Vector3 a, Vector3 b, float t) => a + (b - a) * Mathf.Clamp01(t);
        public static Vector3 MoveTowards(Vector3 c, Vector3 t, float d) => c + (t - c).normalized * Math.Min(d, (t - c).magnitude);
        public static float Dot(Vector3 a, Vector3 b) => a.x * b.x + a.y * b.y + a.z * b.z;
        public static implicit operator Vector2(Vector3 v) => new(v.x, v.y);
    }

    public struct Quaternion
    {
        public float x, y, z, w;
        public static Quaternion identity => new() { w = 1 };
        public static Quaternion Euler(float x, float y, float z) => identity;
        public static Quaternion LookRotation(Vector3 f) => identity;
        public static Quaternion LookRotation(Vector3 f, Vector3 up) => identity;
        public static Quaternion Slerp(Quaternion a, Quaternion b, float t) => a;
        public static Vector3 operator *(Quaternion q, Vector3 v) => v;
        public static Quaternion operator *(Quaternion a, Quaternion b) => a;
    }

    public static class Mathf
    {
        public const float PI = (float)Math.PI;
        public const float Rad2Deg = 57.29578f;
        public const float Deg2Rad = 0.0174533f;
        public static float Abs(float v) => Math.Abs(v);
        public static float Max(float a, float b) => Math.Max(a, b);
        public static int Max(int a, int b) => Math.Max(a, b);
        public static float Min(float a, float b) => Math.Min(a, b);
        public static int Min(int a, int b) => Math.Min(a, b);
        public static float Clamp(float v, float lo, float hi) => v < lo ? lo : (v > hi ? hi : v);
        public static int Clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
        public static float Clamp01(float v) => Clamp(v, 0f, 1f);
        public static float Lerp(float a, float b, float t) => a + (b - a) * Clamp01(t);
        public static float MoveTowards(float c, float t, float d) => Math.Abs(t - c) <= d ? t : c + Math.Sign(t - c) * d;
        public static float Sin(float a) => (float)Math.Sin(a);
        public static float Cos(float a) => (float)Math.Cos(a);
        public static float Round(float v) => (float)Math.Round(v);
        public static int RoundToInt(float v) => (int)Math.Round(v);
        public static float Repeat(float t, float len) => t - (float)Math.Floor(t / len) * len;
        public static float PerlinNoise(float x, float y) => 0.5f;
        public static float SmoothStep(float a, float b, float t) => Lerp(a, b, t * t * (3f - 2f * t));
        public static float Sqrt(float v) => (float)Math.Sqrt(v);
        public static float Atan2(float y, float x) => (float)Math.Atan2(y, x);
        public static float Sign(float v) => Math.Sign(v);
        public static float Pow(float a, float b) => (float)Math.Pow(a, b);
    }

    public struct Color
    {
        public float r, g, b, a;
        public Color(float r, float g, float b) { this.r = r; this.g = g; this.b = b; a = 1f; }
        public Color(float r, float g, float b, float a) { this.r = r; this.g = g; this.b = b; this.a = a; }
        public static Color white => new(1, 1, 1);
        public static Color black => new(0, 0, 0);
        public static Color Lerp(Color x, Color y, float t) =>
            new(x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t, x.b + (y.b - x.b) * t, x.a + (y.a - x.a) * t);
        public static Color operator *(Color c, float k) => new(c.r * k, c.g * k, c.b * k, c.a);
    }

    public struct Color32
    {
        public byte r, g, b, a;
        public static implicit operator Color32(Color c) => new();
        public static implicit operator Color(Color32 c) => new();
    }

    public struct Rect
    {
        public float x, y, width, height;
        public Rect(float x, float y, float w, float h) { this.x = x; this.y = y; width = w; height = h; }
        public Rect(Vector2 pos, Vector2 size) { x = pos.x; y = pos.y; width = size.x; height = size.y; }
    }

    // ── объектная модель ──
    public class Object
    {
        public string name = "";
        public static void Destroy(Object o) { }
        public static void Destroy(Object o, float delay) { }
        public static void DontDestroyOnLoad(Object o) { }
        public static T FindFirstObjectByType<T>() where T : Object => null;
        public static implicit operator bool(Object o) => o != null;
    }

    public class GameObject : Object
    {
        public Transform transform = new();
        public int layer;
        public string tag = "";
        public bool isStatic;
        public GameObject() { transform.gameObject = this; }
        public GameObject(string name) : this() { this.name = name; }
        public GameObject(string name, params Type[] components) : this(name) { }
        public T AddComponent<T>() where T : Component { var c = Activator.CreateInstance<T>(); c.gameObject = this; return c; }
        public T GetComponent<T>() where T : Component => null;
        public void SetActive(bool on) { }
        public bool activeSelf => true;
        public static GameObject CreatePrimitive(PrimitiveType t) => new("prim");
    }

    public class Component : Object
    {
        public GameObject gameObject = new();
        public Transform transform => gameObject.transform;
        public T GetComponent<T>() where T : Component => gameObject.GetComponent<T>();
        public string tag { get => gameObject.tag; set => gameObject.tag = value; }
    }

    public class Transform : Component, IEnumerable
    {
        public Vector3 position, localPosition, localScale = Vector3.one;
        public Quaternion rotation = Quaternion.identity, localRotation = Quaternion.identity;
        public Vector3 forward = Vector3.forward, right = Vector3.right;
        public Vector3 up { get; set; } = Vector3.up;
        public Transform parent;
        public void SetParent(Transform p, bool worldStays) { parent = p; }
        public void Rotate(float x, float y, float z, Space s = Space.Self) { }
        public void Rotate(Vector3 axis, float angle, Space s = Space.Self) { }
        public IEnumerator GetEnumerator() { yield break; }
    }

    public enum Space { World, Self }
    public enum PrimitiveType { Sphere, Capsule, Cylinder, Cube, Plane, Quad }

    public class Behaviour : Component { public bool enabled = true; }

    public class MonoBehaviour : Behaviour
    {
        public Coroutine StartCoroutine(IEnumerator routine) => null;
        public void StopAllCoroutines() { }
    }

    public class Coroutine { }
    public class YieldInstruction { }
    public class WaitForSeconds : YieldInstruction { public WaitForSeconds(float s) { } }

    public class RequireComponent : Attribute { public RequireComponent(Type t) { } }

    // ── рендер/сцена ──
    public class Camera : Behaviour
    {
        public static Camera main => null;
        public float fieldOfView, nearClipPlane, farClipPlane;
        public Color backgroundColor;
        public CameraClearFlags clearFlags;
    }
    public enum CameraClearFlags { Skybox, SolidColor, Depth, Nothing }

    public class AudioListener : Behaviour { }

    public enum LightType { Spot, Directional, Point, Area }
    public enum LightShadows { None, Hard, Soft }
    public class Light : Behaviour
    {
        public LightType type;
        public Color color;
        public float intensity, range, spotAngle, shadowStrength;
        public LightShadows shadows;
    }

    public class Texture : Object { }
    public class Texture2D : Texture
    {
        public TextureWrapMode wrapMode;
        public Texture2D(int w, int h, TextureFormat f, bool mips) { }
        public void SetPixels(Color[] px) { }
        public void Apply() { }
    }
    public enum TextureFormat { RGB24, RGBA32 }
    public enum TextureWrapMode { Repeat, Clamp }

    public class Shader : Object
    {
        public static Shader Find(string name) => null;
    }

    [Flags] public enum MaterialGlobalIlluminationFlags { None = 0, RealtimeEmissive = 1, BakedEmissive = 2 }
    public class Material : Object
    {
        public MaterialGlobalIlluminationFlags globalIlluminationFlags;
        public Color color;
        public Material(Shader s) { }
        public Material(Material src) { }
        public void SetFloat(string k, float v) { }
        public void SetColor(string k, Color v) { }
        public void SetTexture(string k, Texture t) { }
        public void SetTextureScale(string k, Vector2 s) { }
        public void EnableKeyword(string k) { }
    }

    public class Mesh : Object { }
    public class MeshFilter : Component { public Mesh sharedMesh; }
    public class Renderer : Component { public Material sharedMaterial; public Material material; }
    public class MeshRenderer : Renderer { }

    public class Collider : Component { public bool isTrigger; public bool enabled = true; }
    public class BoxCollider : Collider { public Vector3 size, center; }
    public class SphereCollider : Collider { public float radius; }

    public class Rigidbody : Component
    {
        public float mass;
        public bool isKinematic, useGravity = true;
        public Vector3 velocity;
        public void AddForce(Vector3 f) { }
    }

    public class CharacterController : Collider
    {
        public float height, radius;
        public Vector3 center;
        public bool isGrounded => false;
        public void Move(Vector3 motion) { }
    }

    public struct RaycastHit
    {
        public float distance;
        public Vector3 point, normal;
        public Collider collider;
    }
    public enum QueryTriggerInteraction { UseGlobal, Ignore, Collide }
    public static class Physics
    {
        public const int DefaultRaycastLayers = ~4;
        public static bool Raycast(Vector3 o, Vector3 d, out RaycastHit hit, float dist) { hit = default; return false; }
        public static bool Raycast(Vector3 o, Vector3 d, out RaycastHit hit, float dist, int mask) { hit = default; return false; }
        public static bool Raycast(Vector3 o, Vector3 d, out RaycastHit hit, float dist, int mask, QueryTriggerInteraction q) { hit = default; return false; }
        public static bool SphereCast(Vector3 o, float r, Vector3 d, out RaycastHit hit, float dist) { hit = default; return false; }
        public static bool SphereCast(Vector3 o, float r, Vector3 d, out RaycastHit hit, float dist, int mask) { hit = default; return false; }
        public static bool SphereCast(Vector3 o, float r, Vector3 d, out RaycastHit hit, float dist, int mask, QueryTriggerInteraction q) { hit = default; return false; }
    }

    public enum FogMode { Linear = 1, Exponential = 2, ExponentialSquared = 3 }
    public static class RenderSettings
    {
        public static bool fog;
        public static Color fogColor, ambientLight, ambientSkyColor, ambientEquatorColor, ambientGroundColor;
        public static FogMode fogMode;
        public static float fogDensity;
        public static Material skybox;
        public static Rendering.AmbientMode ambientMode;
    }
    namespace Rendering { public enum AmbientMode { Skybox, Trilight, Flat, Custom } }

    public static class QualitySettings
    {
        public static int pixelLightCount, antiAliasing;
        public static float shadowDistance;
    }

    public static class Time
    {
        public static float deltaTime => 0.016f;
        public static float time => 0f;
        public static float unscaledTime => 0f;
        public static float unscaledDeltaTime => 0.016f;
    }

    public enum KeyCode { None, Escape, Tab, Space, Return, E, F, Q, X, C, R, LeftShift, LeftControl, Alpha1, Alpha2, Alpha3 }
    public static class Input
    {
        public static bool GetKey(KeyCode k) => false;
        public static bool GetKeyDown(KeyCode k) => false;
        public static bool GetKeyUp(KeyCode k) => false;
        public static float GetAxis(string n) => 0f;
        public static float GetAxisRaw(string n) => 0f;
        public static bool GetButtonDown(string n) => false;
        public static bool GetMouseButtonDown(int b) => false;
        public static Vector3 mousePosition => Vector3.zero;
    }

    public enum CursorLockMode { None, Locked, Confined }
    public static class Cursor
    {
        public static CursorLockMode lockState;
        public static bool visible;
    }

    public static class Application { public static void Quit() { } }

    public static class Random
    {
        public static int Range(int lo, int hi) => lo;
        public static float Range(float lo, float hi) => lo;
    }

    public static class Debug
    {
        public static void Log(object msg) { }
        public static void LogWarning(object msg) { }
        public static void LogError(object msg) { }
    }

    // ── текст в мире ──
    public enum TextAnchor { UpperLeft, UpperCenter, UpperRight, MiddleLeft, MiddleCenter, MiddleRight, LowerLeft, LowerCenter, LowerRight }
    public enum TextAlignment { Left, Center, Right }
    public enum HorizontalWrapMode { Wrap, Overflow }
    public enum VerticalWrapMode { Truncate, Overflow }

    public class Font : Object
    {
        public Material material;
        public static Font CreateDynamicFontFromOSFont(string name, int size) => new();
        public static Font CreateDynamicFontFromOSFont(string[] names, int size) => new();
    }

    public class TextMesh : Component
    {
        public Font font;
        public string text;
        public int fontSize;
        public float characterSize;
        public TextAnchor anchor;
        public TextAlignment alignment;
        public Color color;
    }

    // ── uGUI ──
    public class RectTransform : Transform
    {
        public Vector2 anchorMin, anchorMax, pivot, anchoredPosition, sizeDelta, offsetMin, offsetMax;
        public Rect rect;
    }

    public enum RenderMode { ScreenSpaceOverlay, ScreenSpaceCamera, WorldSpace }
    public class Canvas : Behaviour
    {
        public RenderMode renderMode;
        public int sortingOrder;
    }

    public class CanvasRenderer : Component { }

    public struct UIVertex
    {
        public Vector3 position, normal;
        public Color32 color;
        public Vector4 uv0;
        public static UIVertex simpleVert => new();
    }
    public struct Vector4 { public float x, y, z, w; }

    public static class RectTransformUtility
    {
        public static bool ScreenPointToLocalPointInRectangle(RectTransform rect, Vector2 screen, Camera cam, out Vector2 local)
        { local = Vector2.zero; return true; }
    }
}

namespace UnityEngine.Events
{
    public delegate void UnityAction();
    public class UnityEvent
    {
        public void AddListener(UnityAction a) { }
        public void RemoveAllListeners() { }
        public void Invoke() { }
    }
}

namespace UnityEngine.EventSystems
{
    public class EventSystem : MonoBehaviour { }
    public class StandaloneInputModule : MonoBehaviour { }
}

namespace UnityEngine.UI
{
    public class VertexHelper
    {
        public int currentVertCount => 0;
        public void Clear() { }
        public void AddVert(UIVertex v) { }
        public void AddTriangle(int a, int b, int c) { }
    }

    public class Graphic : MonoBehaviour
    {
        public RectTransform rectTransform => null;
        public bool raycastTarget = true;
        public Color color;
        public void SetVerticesDirty() { }
        protected virtual void OnPopulateMesh(VertexHelper vh) { }
    }

    public class MaskableGraphic : Graphic { }

    public class CanvasScaler : MonoBehaviour
    {
        public enum ScaleMode { ConstantPixelSize, ScaleWithScreenSize, ConstantPhysicalSize }
        public ScaleMode uiScaleMode;
        public Vector2 referenceResolution;
    }

    public class GraphicRaycaster : MonoBehaviour { }

    public class Text : MaskableGraphic
    {
        public Font font;
        public string text;
        public int fontSize;
        public TextAnchor alignment;
        public HorizontalWrapMode horizontalOverflow;
        public VerticalWrapMode verticalOverflow;
        public bool supportRichText = true;
    }

    public class Image : MaskableGraphic { }

    public class Button : MonoBehaviour
    {
        public Events.UnityEvent onClick = new();
    }
}

namespace UnityEngine.SceneManagement
{
    public struct Scene { public string name; public int buildIndex; }
    public static class SceneManager
    {
        public static Scene GetActiveScene() => default;
        public static void LoadScene(string name) { }
        public static void LoadScene(int buildIndex) { }
    }
}
