using System;
using System.Collections;
using Invector.vCharacterController;
using UnityEngine;


// 1P控制器

public class LocalDwarfController : MonoBehaviour
{
    public int currentPlayerId = -1;
    public bool isSyncAll = false;

    int inputH = -2;
    int inputV = -2;
    int inputJ = 0;
    int inputS = 0;

    int prevInputH = -2;
    int prevInputV = -2;
    int prevInputJ = 0;
    int prevInputS = 0;

    int localFrame = 0;
    int maxServerFrame = 0;

    Vector3 cameraForward = new Vector3(0.0f, 1.0f, 0.0f);
    Rigidbody rb;
    string cameraName = "DwarfCameraMain";
    bool isPauseUpdate = false;

    // 这个结构体用于存储每帧的操作
    struct FixInput
    {
        public bool Space;
        public bool SpaceDown;
        public bool SpaceUp;

        public bool LeftShift;
        public bool LeftShiftDown;
        public bool LeftShiftUp;

        public float Y;
        public float X;

        //添加内容后，记得更新ResetFixInput()
    }

    FixInput fixInput;

    protected virtual void Start()
    {
        // 初始化人物控制器
        InitilizeController();
        InitializeTpCamera();

        rb = GetComponent<Rigidbody>();
        ResetFixInput();

        // 启动协程，每隔0.2~0.4秒进行一次状态同步
        StartCoroutine(AutoSnapshot());
    }

    private void Update()
    {
        // 把本帧的输入保存下来，等待下一次FixUpdate时统一处理

        if (Input.GetKey(KeyCode.Space)) fixInput.Space = true;
        if (Input.GetKeyDown(KeyCode.Space)) fixInput.SpaceDown = true;
        if (Input.GetKeyUp(KeyCode.Space)) fixInput.SpaceUp = true;

        if (Input.GetKey(KeyCode.LeftShift)) fixInput.LeftShift = true;
        if (Input.GetKeyDown(KeyCode.LeftShift)) fixInput.LeftShiftDown = true;
        if (Input.GetKeyUp(KeyCode.LeftShift)) fixInput.LeftShiftUp = true;

        fixInput.Y += Input.GetAxis(rotateCameraYInput);
        fixInput.X += Input.GetAxis(rotateCameraXInput);
    }

    // 下面的这个FixUpdate才是真正处理联网逻辑的函数
    // - 为什么不用Update处理呢？
    // - 不同人的电脑配置不同，Update的帧数也不同，但数据的收发、处理都是和帧序号相关的，容易形成混乱
    // - 所以统一用每秒50帧的速率来处理
    private void FixedUpdate()
    {
        if (!isPauseUpdate)
            NaturalUpdate();
        else
            Debug.Log("暂停更新帧");

        // 处理完成，清空输入
        ResetFixInput();
    }

    void ResetFixInput()
    {
        fixInput.Space = false;
        fixInput.SpaceDown = false;
        fixInput.SpaceUp = false;

        fixInput.LeftShift = false;
        fixInput.LeftShiftDown = false;
        fixInput.LeftShiftUp = false;

        fixInput.Y = 0;
        fixInput.X = 0;
    }

    // 计算一帧，用于更新本地玩家
    // 这里的具体逻辑不属于网络编程的范畴，略读即可
    void NaturalUpdate()
    {
        // 更新本机帧号
        localFrame++;

        InputHandle(); // 处理玩家输入
        NetworkHandle(); // 处理网络逻辑
        //cc.UpdateAnimator(); // 更新动画状态

        cc.UpdateMotor(); // 更新人物
        cc.ControlLocomotionType(); // 更新运动状态
        cc.ControlRotationType(); // 更新旋转状态
    }

    // 每帧处理网络逻辑，在需要时向服务器上传数据
    void NetworkHandle()
    {
        if (!inputEnabled) return;

        // 处理相机输入，获取玩家当前的方向
        var right = Vector3.right;
        var forward = Vector3.forward;
        var cameraMain = tpCamera.GetComponent<Camera>();
        if (cameraMain)
        {
            right = cameraMain.transform.right;
            right.y = 0.0f;
            right.Normalize();
            forward = cameraMain.transform.forward;
            forward.y = 0.0f;
            forward.Normalize();
        }

        // 当前方向与上一帧的差值
        Vector3 fowardDiff = cameraForward.normalized - forward.normalized;

        // 检查是否有按键变化等
        bool keyChange = prevInputH != inputH || prevInputV != inputV || prevInputJ != inputJ || prevInputS != inputS;
        bool keyPress = inputH != 0 || inputV != 0 || inputJ != 0 || inputS != 0;

        //如果 按键情况改变 || 持续按键且人物朝向改变 则发送操作
        if (keyChange || (keyPress && fowardDiff.sqrMagnitude > 0.0f) || isSyncAll)
        {
            // 更新按键记录
            prevInputH = inputH;
            prevInputV = inputV;
            prevInputJ = inputJ;
            prevInputS = inputS;

            // 更新朝向记录
            cameraForward = forward;

            // 发送操作
            SendDwarfAction(inputH, inputV, inputJ, inputS, cameraForward.x, cameraForward.z);
        }
    }

    // 发送一次操作
    void SendDwarfAction(int h, int v, int jump, int sprint, float fx, float fz)
    {
        Globals.Instance.NetworkForCS.ActionRequest(h, v, jump, sprint, fx, fz);
    }

    // 每隔0.2~0.4s，自动同步一次本机玩家状态
    IEnumerator AutoSnapshot()
    {
        while (true)
        {
            // SendLocalSnapshot();
            SendSnapshot();
            float waitTime = UnityEngine.Random.Range(0.2f, 0.4f);
            yield return new WaitForSeconds(waitTime);
        }
    }

    // 发送本机玩家状态
    void SendSnapshot()
    {
        Vector3 pos = rb.position;
        Quaternion rot = rb.rotation;
        Vector3 scl = transform.localScale;

        Globals.Instance.NetworkForCS.SnapshotRequest(localFrame, pos, rot, scl);
    }

    // 处理输入
    protected virtual void InputHandle()
    {
        MoveInput();
        CameraInput();
        SprintInput();
        JumpInput();
    }

    // 处理WASD输入
    public virtual void MoveInput()
    {
        inputH = (int)Input.GetAxisRaw("Horizontal");
        inputV = (int)Input.GetAxisRaw("Vertical");

        cc.input.x = inputH;
        cc.input.z = inputV;
    }

    // 处理相机输入
    protected virtual void CameraInput()
    {
        if (!cameraMain)
        {
            if (!Camera.main) Debug.Log("Missing a Camera with the tag MainCamera, please add one.");
            else
            {
                cameraMain = GameObject.Find(cameraName).GetComponent<Camera>();
                cc.rotateTarget = cameraMain.transform;
            }
        }

        if (cameraMain)
        {
            Vector3 forward;
            Vector3 right;

            forward = cameraMain.transform.forward;
            forward.y = 0.0f;
            forward.Normalize();

            float fx = forward.x;
            float fz = forward.z;

            forward = new Vector3(0.0f, 0.0f, 1.0f);
            right = new Vector3(1.0f, 0.0f, 0.0f);

            forward.x = fx;
            forward.y = 0.0f;
            forward.z = fz;
            forward.Normalize();
            right = Vector3.Cross(Vector3.up, forward);
            right.Normalize();

            // 更新本机人物的朝向
            cc.UpdateMoveDirectionRemote(forward, right);
        }

        // 旋转本地相机
        if (tpCamera == null) return;

        var Y = fixInput.Y;
        var X = fixInput.X;

        tpCamera.RotateCamera(X, Y);
    }

    // 处理冲刺输入
    protected virtual void SprintInput()
    {
        inputS = fixInput.LeftShift ? 1 : 0;
        if (fixInput.LeftShiftDown)
            cc.Sprint(true);
        else if (fixInput.LeftShiftUp)
            cc.Sprint(false);
    }

    // 检查跳跃条件
    protected virtual bool JumpConditions()
    {
        return cc.isGrounded && cc.GroundAngle() < cc.slopeLimit && !cc.isJumping && !cc.stopMove;
    }

    // 处理跳跃输入
    protected virtual void JumpInput()
    {
        inputJ = fixInput.SpaceDown ? 1 : 0;
        if (fixInput.SpaceDown && JumpConditions())
            cc.Jump();
    }

    #region Basic Locomotion Inputs

    protected virtual void InitilizeController()
    {
        cc = GetComponent<vThirdPersonController>();

        if (cc != null)
            cc.Init();
    }

    protected virtual void InitializeTpCamera()
    {
        if (tpCamera == null)
        {
            tpCamera = GameObject.Find(cameraName).GetComponent<vThirdPersonCamera>();
            if (tpCamera == null)
                return;
            if (tpCamera)
            {
                tpCamera.SetMainTarget(this.transform);
                tpCamera.Init();
            }
        }
    }

    #endregion

    public void SetColor(int color)
    {
        if (null != Renderer)
        {
            var bytes = BitConverter.GetBytes(color);
            Renderer.material.color = new Color(bytes[0] / 255.0f, bytes[1] / 255.0f, bytes[2] / 255.0f, 1);
        }
    }

    #region Variables

    [Header("Controller Input")] public bool inputEnabled = true;
    public string horizontalInput = "Horizontal";
    public string verticallInput = "Vertical";
    public KeyCode jumpInput = KeyCode.Space;
    public KeyCode strafeInput = KeyCode.Tab;
    public KeyCode sprintInput = KeyCode.LeftShift;

    [Header("Camera Input")] public string rotateCameraXInput = "Mouse X";
    public string rotateCameraYInput = "Mouse Y";

    [HideInInspector] public vThirdPersonController cc;
    [HideInInspector] public vThirdPersonCamera tpCamera;
    [HideInInspector] public Camera cameraMain;

    public Renderer Renderer;

    #endregion
}