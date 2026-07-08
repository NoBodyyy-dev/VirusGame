using UnityEngine;

namespace Virus.Player
{
    // Порт player.gd: CharacterBody3D + move_and_slide → CharacterController.
    // Третье лицо: пивот рыскания + камера на «штанге». Койот-тайм, буфер прыжка,
    // спринт, штраф скорости от груза. Ощущение придётся дотюнить в Unity —
    // move_and_slide и CharacterController.Move ведут себя по-разному на склонах.
    [RequireComponent(typeof(CharacterController))]
    public class VirusPlayer : MonoBehaviour
    {
        const float Gravity = 26f, JumpV = 9.5f, Coyote = 0.12f, JumpBuffer = 0.14f;
        const float MouseSens = 0.12f, AccelGround = 42f, AccelAir = 16f;

        public bool controlEnabled = true;
        public float carryFactor = 1f;
        public bool carrying = false;

        public float baseSpeed = 6f, sprintSpeed = 9.2f;

        CharacterController _cc;
        Transform _yaw, _pitch, _cam;
        Vector3 _vel;
        float _coyoteT, _jumpBufT, _camPitch;
        bool _wasGrounded = true;

        void Awake()
        {
            _cc = GetComponent<CharacterController>();
            _cc.height = 1.7f; _cc.radius = 0.45f; _cc.center = new Vector3(0, 0.95f, 0);

            _yaw = new GameObject("Yaw").transform;
            _yaw.SetParent(transform, false);
            _yaw.localPosition = new Vector3(0, 1.5f, 0);
            _pitch = new GameObject("Pitch").transform;
            _pitch.SetParent(_yaw, false);
            var camGo = new GameObject("Camera", typeof(Camera));
            camGo.tag = "MainCamera";
            _cam = camGo.transform;
            _cam.SetParent(_pitch, false);
            _cam.localPosition = new Vector3(0, 0, -5.2f);   // «спринг-арм» за спиной
            _cam.localRotation = Quaternion.identity;

            Cursor.lockState = CursorLockMode.Locked;
        }

        void Update()
        {
            if (controlEnabled)
            {
                float mx = Input.GetAxisRaw("Mouse X") * MouseSens * 60f * Time.deltaTime;
                float my = Input.GetAxisRaw("Mouse Y") * MouseSens * 60f * Time.deltaTime;
                _yaw.Rotate(0, mx, 0, Space.Self);
                _camPitch = Mathf.Clamp(_camPitch - my, -65f, 18f);
                _pitch.localRotation = Quaternion.Euler(_camPitch, 0, 0);
            }

            bool grounded = _cc.isGrounded;
            if (grounded) { _coyoteT = Coyote; if (!_wasGrounded) OnLand(); }
            else _coyoteT = Mathf.Max(_coyoteT - Time.deltaTime, 0f);
            _wasGrounded = grounded;

            _jumpBufT = Mathf.Max(_jumpBufT - Time.deltaTime, 0f);
            if (controlEnabled && !carrying && Input.GetButtonDown("Jump")) _jumpBufT = JumpBuffer;

            Vector3 input = Vector3.zero;
            if (controlEnabled)
            {
                float h = Input.GetAxisRaw("Horizontal"), v = Input.GetAxisRaw("Vertical");
                input = (_yaw.right * h + _yaw.forward * v);
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

            // модель поворачивается по направлению движения (визуал — в TODO)
            if (input.sqrMagnitude > 0.01f)
                transform.rotation = Quaternion.Slerp(transform.rotation,
                    Quaternion.LookRotation(new Vector3(input.x, 0, input.z)), 10f * Time.deltaTime);
        }

        void OnLand() { /* Sfx.Play("land") — в аудио-порте */ }

        public Vector3 LookDir()
        {
            var d = _yaw.forward; d.y = 0f;
            return d.sqrMagnitude > 0.01f ? d.normalized : Vector3.forward;
        }
    }
}
