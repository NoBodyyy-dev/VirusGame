using UnityEngine;
using Virus.Core;
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

        // множители мутаторов рейда (НЕВЕСОМОСТЬ, СКОЛЬЗКИЙ ПОЛ…)
        public float gravityScale = 1f, accelScale = 1f;

        // статусы (метки времени Time.time): ловушки и активки
        public float hasteUntil, slowUntil, lockedUntil;
        public bool bug;
        public bool Morphed { get; private set; }
        public System.Action morphBroken;   // морф слетел от движения

        CharacterController _cc;
        Transform _yaw, _pitch, _cam, _model;
        GameObject _crate;      // маскировка «ложный файл»
        string _modelSig = "";
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
            PostFx.AttachCamera(_camera);
            PostFx.EnsureVolume();

            RebuildModel();
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
        }

        // ── скин вируса: полиморфный, зависит от ветки/уровня/доп. ветки (VirusModel) ──
        void RebuildModel()
        {
            var s = GameState.I;
            string cls = s.DisplayClass();
            int stage = s.EvolveStage();
            string sec = s.DisplaySecondary();
            _modelSig = $"{cls}:{stage}:{sec}:{bug}";

            var oldRot = _model != null ? _model.rotation : Quaternion.identity;
            if (_model != null) Destroy(_model.gameObject);
            _model = (bug
                ? VirusModel.BuildBug(transform, GameData.CLASSES[cls].color)
                : VirusModel.Build(transform, cls, stage, sec)).transform;
            _model.rotation = oldRot;
            SetLayerDeep(_model, 2);
            if (Morphed) _model.gameObject.SetActive(false);   // не светить скин из-под маскировки
        }

        static void SetLayerDeep(Transform t, int layer)
        {
            t.gameObject.layer = layer;
            foreach (Transform c in t) SetLayerDeep(c, layer);
        }

        // перестройка при смене ветки/уровня/сброса/бага
        void EnsureModel()
        {
            var s = GameState.I;
            string sig = $"{s.DisplayClass()}:{s.EvolveStage()}:{s.DisplaySecondary()}:{bug}";
            if (sig != _modelSig) RebuildModel();
        }

        public void SetBug(bool on)
        {
            if (bug == on) return;
            bug = on;
            if (on) SetMorph(false);
            RebuildModel();
        }

        // «ложный файл»: игрок выглядит как ящик, движение снимает морф
        public void SetMorph(bool on)
        {
            if (Morphed == on) return;
            Morphed = on;
            if (on && _crate == null) _crate = VirusModel.BuildCrate(transform);
            if (_crate != null) _crate.SetActive(on);
            if (_model != null) _model.gameObject.SetActive(!on);
        }

        public bool Locked => Time.time < lockedUntil;

        // рывок: бросок вперёд по направлению взгляда (работает даже с грузом)
        public void Dash()
        {
            var d = LookDir();
            _vel += d * 14f + Vector3.up * 2.5f;
        }

        void Update()
        {
            EnsureModel();

            // ESC — меню паузы (панели закрывают себя сами); клик — вернуть захват
            // курсора, но ТОЛЬКО пока управление активно: на экране результатов и
            // в диалогах клик по кнопке не должен красть курсор (кнопка «умирала»)
            if (Input.GetKeyDown(KeyCode.Escape) && controlEnabled
                && !UI.EvolutionUI.IsOpen && !UI.PuzzleUI.IsOpen && !UI.PauseMenu.IsOpen)
                UI.PauseMenu.Toggle();
            else if (Input.GetMouseButtonDown(0) && controlEnabled
                     && Cursor.lockState != CursorLockMode.Locked
                     && !UI.EvolutionUI.IsOpen && !UI.PuzzleUI.IsOpen && !UI.PauseMenu.IsOpen)
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
            bool canAct = controlEnabled && !Locked;
            if (canAct && !carrying && !bug && Input.GetButtonDown("Jump")) _jumpBufT = JumpBuffer;

            Vector3 input = Vector3.zero;
            if (canAct)
            {
                float h = Input.GetAxisRaw("Horizontal"), v = Input.GetAxisRaw("Vertical");
                input = _yaw.right * h + _yaw.forward * v;
                input.y = 0f;
                if (input.sqrMagnitude > 1f) input.Normalize();
            }

            // движение снимает «ложный файл»
            if (Morphed && (input.sqrMagnitude > 0.01f || _jumpBufT > 0f))
            {
                SetMorph(false);
                morphBroken?.Invoke();
            }

            bool sprinting = canAct && Input.GetKey(KeyCode.LeftShift) && !bug;
            // скорость: эволюция растит базу, червь быстрее всех; статусы ловушек/активок
            float evo = GameState.I.EvoBonus("speed") + (GameState.I.HasPassive("worm") ? 0.9f : 0f);
            float speed = bug ? 3.4f : ((sprinting ? sprintSpeed : baseSpeed) + evo) * carryFactor;
            if (Time.time < hasteUntil) speed *= 1.45f;
            if (Time.time < slowUntil) speed *= 0.55f;
            float accel = (grounded ? AccelGround : AccelAir) * accelScale;
            _vel.x = Mathf.MoveTowards(_vel.x, input.x * speed, accel * Time.deltaTime);
            _vel.z = Mathf.MoveTowards(_vel.z, input.z * speed, accel * Time.deltaTime);

            if (grounded && _vel.y < 0f) _vel.y = -2f;
            if (_jumpBufT > 0f && _coyoteT > 0f) { _vel.y = JumpV; _jumpBufT = 0f; _coyoteT = 0f; }
            _vel.y -= Gravity * gravityScale * Time.deltaTime;

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

        // ── тряска камеры (удары, крюк) ──
        float _shake;
        System.Random _shakeRng = new();

        public void Shake(float amount) => _shake = Mathf.Max(_shake, amount);

        float ShakeOff() => ((float)_shakeRng.NextDouble() * 2f - 1f) * _shake;

        // ── спринг-арм: камера не проваливается сквозь стены ──
        void LateUpdate()
        {
            Vector3 origin = _pitch.position;
            Vector3 dir = -_pitch.forward;
            float dist = ArmLen;
            if (Physics.SphereCast(origin, ArmRadius, dir, out var hit, ArmLen,
                    Physics.DefaultRaycastLayers, QueryTriggerInteraction.Ignore))
                dist = Mathf.Max(hit.distance - 0.08f, 0.35f);
            _shake = Mathf.Max(_shake - Time.deltaTime * 1.6f, 0f);
            _cam.localPosition = new Vector3(ShakeOff() * 0.25f, ShakeOff() * 0.2f, -dist);
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
