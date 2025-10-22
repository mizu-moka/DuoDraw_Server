using System;
using System.Collections;
using System.Collections.Generic;
using Invector.vCharacterController;
using UnityEngine;

// 定义格式：玩家操作数据包
public class InputActionInfo
{
    public int id = 0; //玩家id
    public int frame = 0; //当前帧号
    public int inputH = 0; //水平（AD）输入
    public int inputV = 0; //垂直（WS）输入
    public int inputJ = 0; //跳跃输入
    public int inputS = 0; //冲刺输入
    public Vector3 forward = new Vector3(0.0f, 0.0f, 1.0f); //玩家朝向
    public Vector3 right = new Vector3(1.0f, 0.0f, 0.0f); //玩家朝向

    public InputActionInfo(int i, int f, int h, int v, int jump, int sprint, float fx, float fz)
    {
        id = i;
        frame = f;
        inputH = h;
        inputV = v;
        inputJ = jump;
        inputS = sprint;
        forward.x = fx;
        forward.y = 0.0f;
        forward.z = fz;
        forward.Normalize();
        right = Vector3.Cross(Vector3.up, forward);
        right.Normalize();
    }
}

// 3P控制器
public class RemoteDwarfController : MonoBehaviour
{
    public int currentPlayerId = -1;
    public int localFrame;
    public int serverFrame = 0;
    public int currentFrame = 0;

    List<InputActionInfo> inputActions = new List<InputActionInfo>(); //输入队列
    InputActionInfo MyInputAction = new InputActionInfo(0, 0, 0, 0, 0, 0, 0, 0);
    Coroutine addPosSmooth;
    Rigidbody rb;
    int preInputS = 0;
    int preInputJ = 0;
    int tempIndex = 0;

    int moveCnt = 0;
    int ssFrame = 0;

    protected virtual void Start()
    {
        InitilizeController();
        InitializeTpCamera();
        rb = GetComponent<Rigidbody>();
        localFrame = Globals.Instance.DataMgr.CurrentFrame;
    }


    // 检查操作列表，从中选择操作来执行
    public bool UpdateActions(int maxFrame)
    {
        // 如果待办操作列表不为空
        int count = 0;
        foreach (var action in inputActions)
        {
            MyInputAction = action;
            UpdateMove();

            currentFrame = action.frame;
            count += 1;
        }
        // Debug.Log("UpdateActions3");

        inputActions.RemoveRange(0, count);
        return false;
    }

    // 实际执行一条操作
    void UpdateMove()
    {
        InputHandle(); // 处理输入
        cc.UpdateAnimator(); // 更新动画机
        cc.UpdateMotor(); // 更新模型
        cc.ControlLocomotionType(); // 更新运动类型
        cc.ControlRotationType(); // 更新旋转类型
    }

    // 将收到的数据包添加到列表中
    public void AddRemoteAction(int id, int frame, int h, int v, int jump, int sprint, float fx, float fz)
    {
        // Debug.Log("添加了action，其frame=" + frame);
        inputActions.Add(new InputActionInfo(id, frame, h, v, jump, sprint, fx, fz));
    }

    // 处理真正操控这个玩家的客户端发来的Snapshot数据包
    public void HandleSnapshot(int frame, Vector3 pos, Quaternion rot, Vector3 scl)
    {
        // 将发来的Position应用到小人身上，使用SmoothPos()来平滑地修改小人的位置
        Vector3 posDiff = pos - transform.position; // 位置的差值
        float posSmoothDuration = 0.4f; // 进行位置平滑的时长

        // addPosSmooth是负责持续处理位置平滑的协程
        // 由于有新的数据包需要处理，先停止原来的协程
        if (addPosSmooth != null)
            StopCoroutine(addPosSmooth);

        if (posDiff.sqrMagnitude > 10)
        {
            // 如果玩家实际位置与预期位置相差过大，则触发强制同步
            rb.position = pos;
            rb.velocity = Vector3.zero;
            Debug.Log("对玩家" + currentPlayerId + "进行强制位置同步");
        }
        else
            // 如果玩家实际位置与预期位置相近，则开一个新协程进行位置平滑
            // 这个操作可以看成是：在0.4秒内把posDiff均匀地加到玩家的position上
            addPosSmooth = StartCoroutine(AddPosSmooth(posDiff, posSmoothDuration));

        // 人物缩放比例
        transform.localScale = scl;
        transform.rotation = rot;
    }

    // 协程，负责持续对玩家的位置进行平滑
    IEnumerator AddPosSmooth(Vector3 addPos, float duration)
    {
        Vector3 oriPos = new Vector3(0, 0, 0);
        float timer = 0f;
        float progress = 0f;
        while (!Mathf.Approximately(progress, 1f) && progress < 1f)
        {
            timer += Time.deltaTime;
            progress = timer / duration;
            if (progress > 1) break;
            Vector3 newPos = SmoothPos(new Vector3(0, 0, 0), addPos, progress);
            rb.position += newPos - oriPos;
            oriPos = newPos;
            yield return 0;
        }
    }

    // 根据 progress（ 取值范围 0~1.0 ）返回 now 和 target 之间的一个值
    Vector3 SmoothPos(Vector3 now, Vector3 target, float progress)
    {
        Vector3 res;
        res.x = Mathf.Lerp(now.x, target.x, progress);
        res.y = Mathf.Lerp(now.y, target.y, progress);
        res.z = Mathf.Lerp(now.z, target.z, progress);
        return res;
    }

    // 以下是操作处理部分，做法和LocalDwarfController相同

    protected virtual void InputHandle()
    {
        MoveInput();
        CameraInput();
        SprintInput();
        JumpInput();
    }

    public virtual void MoveInput()
    {
        cc.input.x = MyInputAction.inputH;
        cc.input.z = MyInputAction.inputV;
        // Debug.Log(currentFrame + ":" + MyInputAction.inputH + " " + MyInputAction.inputV);
        string inputInfo = currentFrame + ":" + MyInputAction.inputH + " " + MyInputAction.inputV;
        if (MyInputAction.inputJ != 0)
            inputInfo += " jump";
        if (MyInputAction.inputS != 0)
            inputInfo += " Sprint";
        // Debug.Log(inputInfo);
    }

    protected virtual void CameraInput()
    {
        cc.UpdateMoveDirectionRemote(MyInputAction.forward, MyInputAction.right);
    }

    protected virtual void SprintInput()
    {
        bool isDown = (MyInputAction.inputS != 0) && (preInputS != MyInputAction.inputS);
        bool isUp = (MyInputAction.inputS == 0) && (preInputS != MyInputAction.inputS);

        if (isDown)
            cc.Sprint(true);
        else if (isUp)
            cc.Sprint(false);

        preInputS = MyInputAction.inputS;
    }

    protected virtual void JumpInput()
    {
        bool isDown = (MyInputAction.inputJ != 0) && (preInputJ != MyInputAction.inputJ);
        if (isDown && JumpConditions())
            cc.Jump();
        preInputJ = MyInputAction.inputJ;
    }

    protected virtual bool JumpConditions()
    {
        return cc.isGrounded && cc.GroundAngle() < cc.slopeLimit && !cc.isJumping && !cc.stopMove;
    }

    //public virtual void OnAnimatorMove()
    //{
    //    cc.ControlAnimatorRootMotion(); // handle root motion animations 
    //}

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
            tpCamera = GameObject.Find("DwarfCameraRemote" + currentPlayerId).GetComponent<vThirdPersonCamera>();
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