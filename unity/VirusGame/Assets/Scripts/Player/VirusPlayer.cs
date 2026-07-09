using UnityEngine;
using Virus.Util;

namespace Virus.Player
{
    // Порт player.gd (третье лицо). Схема как в Godot:
    //  • корень (CharacterController) НЕ вращается;
    //  • мышь крутит ТОЛЬКО камеру (yaw-пивот + pitch), WASD — только движение;
    //  • к направлению движения поворачивается только МОДЕЛЬ (скин вируса);
    //  • камера на «спринг-арме»: сферакаст не даёт ей проваливаться в стены.
    [RequireComponent(typeof(CharacterController))]
    public class VirusPlayer : MonoBehaviour
    {
        const float Gravity = 26f, JumpV = 9.5f, Coyote = 0.12f, JumpBuffer = 0.14f;
        const float AccelGround = 42f, AccelAir = 16f;
        const float MouseSens = 2.4f;              // градусы на единицу дельты мыши
        const float ArmLen = 5.2f, ArmRadius = 0.28f, BaseFov = 68f;

        public bool controlEnabled = true;
        public float carryFactor = 1f;
        public bool carrying = false;
        public float baseSpeed = 6f, sprintSpeed = 9.2f;

        static readonly Color ProtoColor = new(0.604f, 0.722f, 0.784f);   // ПРОТО-ШТАММ #9ab8c8

        CharacterController _cc;
        Transform _yaw, _pitch, _cam, _model;
        Camera _camera;
        Vector3 _vel;
        float _coyoteT, _jumpBufT, _pitchDeg = -14f;
        bool _wasGrounded = true;

        void Awake()
        {
            gameObject.layer = 2;   // IgnoreRaycast: спринг-арм не бьётся об игрока
            _cc = GetComponent<CharacterController>();
            _cc.height = 1.7f; _cc.radius = 0.45f; _cc.center = new Vector3(0, 0.95f, 0);

            // камера: yaw → pitch → cam (корень игрока не вращается вообще)
            _yaw = new GameObject("Yaw").transform;
            _yaw.SetParent(transform, false);
            _yaw.localPosition = new Vector3(0, 1.5f, 0);
            _pitch = new GameObject("Pitch").transform;
            _pitch.SetParent(_yaw, false);
            _pitch.localRotation = Quaternion.Euler(_pitchDeg, 0, 0);
            var camGo = new GameObject("Camera", typeof(Camera), typeof(AudioListener));
            camGo.tag = "MainCamera";
            _camera = camGo.GetComponent<Camera>();
            _camera.fieldOfView = BaseFov;
            _camera.nearClipPlane = 0.08f;
            _camera.farClipPlane = 420f;
            _camera.backgroundColor = new Color(0.012f, 0.02f, 0.045f);
            _cam = camGo.transform;
            _cam.SetParent(_pitch, false);
            _cam.localPosition = new Vector3(0, 0, -ArmLen);

            BuildModel();
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
        }

        // ── скин вируса (упрощённый порт virus_models.gd: ядро, глаза, шипы) ──
        void BuildModel()
        {
            _model = new GameObject("Model").transform;
            _model.SetParent(transform, false);

            var shell = Mats.Plastic(new Color(0.10f, 0.13f, 0.16f));
            var glow = Mats.Neon(ProtoColor, 1.6f);
            var glowSoft = Mats.Neon(ProtoColor, 0.7f);

            // тело-капля
            Prim(PrimitiveType.Sphere, _model, new Vector3(0, 0.92f, 0), new Vector3(0.92f, 1.14f, 0.92f), shell);
            // светящееся ядро и «мембрана»
            Prim(PrimitiveType.Sphere, _model, new Vector3(0, 1.02f, 0.14f), Vector3.one * 0.5f, glow);
            Prim(PrimitiveType.Sphere, _model, new Vector3(0, 0.62f, 0.0f), new Vector3(0.7f, 0.42f, 0.7f), glowSoft);
            // глаза
            Prim(PrimitiveType.Sphere, _model, new Vector3(-0.17f, 1.24f, 0.36f), Vector3.one * 0.13f, Mats.Neon(Color.white, 2.2f));
            Prim(PrimitiveType.Sphere, _model, new Vector3(0.17f, 1.24f, 0.36f), Vector3.one * 0.13f, Mats.Neon(Color.white, 2.2f));
            // шипы по кругу
            for (int i = 0; i < 6; i++)
            {
                float a = i * Mathf.PI * 2f / 6f;
                var dir = new Vector3(Mathf.Cos(a), 0.35f, Mathf.Sin(a)).normalized;
                var spike = Prim(PrimitiveType.Capsule, _model,
                    new Vector3(0, 0.95f, 0) + dir * 0.52f, new Vector3(0.13f, 0.3f, 0.13f), shell);
                spike.transform.up = dir;
                // светящийся кончик
                Prim(PrimitiveType.Sphere, _model, new Vector3(0, 0.95f, 0) + dir * 0.82f, Vector3.one * 0.09f, glowSoft);
            }
            // свет штамма (как OmniLight у Godot-игрока)
            var l = new GameObject("glow").AddComponent<Light>();
            l.transform.SetParent(_model, false);
            l.transform.localPosition = new Vector3(0, 1.2f, 0);
            l.type = LightType.Point;
            l.color = ProtoColor;
            l.intensity = 1.3f;
            l.range = 5f;
        }

        static GameObject Prim(PrimitiveType t, Transform parent, Vector3 pos, Vector3 scale, Material m)
        {
            var go = GameObject.CreatePrimitive(t);
            Object.Destroy(go.GetComponent<Collider>());   // скин не должен толкаться
            go.layer = 2;
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localScale = scale;
            go.GetComponent<MeshRenderer>().sharedMaterial = m;
            return go;
        }

        void Update()
        {
            // курсор: ESC — отпустить, клик — снова захватить
            if (Input.GetKeyDown(KeyCode.Escape))
            { Cursor.lockState = CursorLockMode.None; Cursor.visible = true; }
            else if (Input.GetMouseButtonDown(0) && Cursor.lockState != CursorLockMode.Locked)
            { Cursor.lockState = CursorLockMode.Locked; Cursor.visible = false; }

            bool look = controlEnabled && Cursor.lockState == CursorLockMode.Locked;

            // ── камера: ТОЛЬКО мышь (дельта мыши уже покадровая — без deltaTime)
            if (look)
            {
                _yaw.Rotate(0f, Input.GetAxisRaw("Mouse X") * MouseSens, 0f, Space.Self);
                _pitchDeg = Mathf.Clamp(_pitchDeg - Input.GetAxisRaw("Mouse Y") * MouseSens, -65f, 18f);
                _pitch.localRotation = Quaternion.Euler(_pitchDeg, 0, 0);
            }

            // ── движение: ТОЛЬКО WASD, относительно направления камеры (yaw)
            bool grounded = _cc.isGrounded;
            if (grounded) _coyoteT = Coyote;
            else _coyoteT = Mathf.Max(_coyoteT - Time.deltaTime, 0f);
            _wasGrounded = grounded;

            _jumpBufT = Mathf.Max(_jumpBufT - Time.deltaTime, 0f);
            if (controlEnabled && !carrying && Input.GetButtonDown("Jump")) _jumpBufT = JumpBuffer;

            Vector3 input = Vector3.zero;
            if (controlEnabled)
            {
                float h = Input.GetAxisRaw("Horizontal"), v = Input.GetAxisRaw("Vertical");
                input = _yaw.right * h + _yaw.forward * v;
                input.y = 0f;
                if (input.sqrMagnitude > 1f) input.Normalize();
            }

            bool sprinting = controlEnabled && Input.GetKey(KeyCode.LeftShift);
            float speed = (sprinting ? sprintSpeed : baseSpeed) * carryFactor;
            float accel = grounded ? AccelGround : AccelAir;
            _vel.x = Mathf.MoveTowards(_vel.x, input.x * speed, accel * Time.deltaTime);
            _vel.z = Mathf.MoveTowards(_vel.z, input.z * speed, accel * Time.deltaTime);

            if (grounded && _vel.y < 0f) _vel.y = -2f;
            if (_jumpBufT > 0f && _coyoteT > 0f) { _vel.y = JumpV; _jumpBufT = 0f; _coyoteT = 0f; }
            _vel.y -= Gravity * Time.deltaTime;

            _cc.Move(_vel * Time.deltaTime);

            // поворачивается ТОЛЬКО модель — камера от движения не зависит
            var planar = new Vector3(input.x, 0, input.z);
            if (planar.sqrMagnitude > 0.01f)
                _model.rotation = Quaternion.Slerp(_model.rotation,
                    Quaternion.LookRotation(planar), 10f * Time.deltaTime);

            // FOV-кик на спринте (как в Godot)
            float planarSpeed = new Vector2(_vel.x, _vel.z).magnitude;
            float targetFov = BaseFov + (sprinting && planarSpeed > 4f ? 6f : 0f);
            _camera.fieldOfView = Mathf.Lerp(_camera.fieldOfView, targetFov, 6f * Time.deltaTime);
        }

        // ── спринг-арм: камера не проваливается сквозь стены ──
        void LateUpdate()
        {
            Vector3 origin = _pitch.position;
            Vector3 dir = -_pitch.forward;
            float dist = ArmLen;
            if (Physics.SphereCast(origin, ArmRadius, dir, out var hit, ArmLen,
                    Physics.DefaultRaycastLayers, QueryTriggerInteraction.Ignore))
                dist = Mathf.Max(hit.distance - 0.08f, 0.35f);
            _cam.localPosition = new Vector3(0, 0, -dist);
        }

        public Vector3 LookDir()
        {
            var d = _yaw.forward; d.y = 0f;
            return d.sqrMagnitude > 0.01f ? d.normalized : Vector3.forward;
        }

        /// Мгновенный перенос (нокдаун/зип-лайн): CC надо выключить на кадр.
        public void Teleport(Vector3 pos)
        {
            _cc.enabled = false;
            transform.position = pos;
            _vel = Vector3.zero;
            _cc.enabled = true;
        }

        /// Импульс (ловушка ударила, рэгдолл-лайт).
        public void Impulse(Vector3 v) => _vel += v;

        public float PlanarSpeed => new Vector2(_vel.x, _vel.z).magnitude;
    }
}
