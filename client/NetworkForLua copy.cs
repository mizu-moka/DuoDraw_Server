using SLua;
using UnityEngine;

[CustomLuaClass]
public class NetworkForLua
{
    public void RecvConnectOK()
    {
        Debug.Log("连接服务器成功");
        LoginButton btn = GameObject.Find("Play Button").GetComponent<LoginButton>();
        btn.Login();
    }

    // 登录后，为本机玩家设置ID
    public void SetCurrentPlayerResponse(int id, string currentPlayerName, int color)
    {
        Globals.Instance.DataMgr.CurrentPlayerId = id;
        Globals.Instance.DataMgr.CurrentPlayerName = currentPlayerName;
        Globals.Instance.DataMgr.CurrentPlayerColor = color;

        if (id != -1)
        {
            Debug.Log("已登录，本机用户 ID = " + Globals.Instance.DataMgr.CurrentPlayerId + " PlayerName =" + Globals.Instance.DataMgr.CurrentPlayerName);
        }
        else
        {
            Debug.Log("登录失败，原因可能是密码错误或已在线，请关闭客户端并重试");
        }
    }

    // 创建玩家
    public void CreatePlayerResponse(int id, string name, int color, float x, float y, float z)
    {
        GameObject tempGo;
        if (Globals.Instance.DataMgr.AllPlayers.TryGetValue(id, out tempGo))
        {
            if (null != tempGo)
            {
                return;
            }
            else
            {
                Globals.Instance.DataMgr.AllPlayers.Remove(id);
            }
        }

        Vector3 pos = new Vector3(x, y, z);

        // 创建本机玩家
        if (Globals.Instance.DataMgr.CurrentPlayerId == id)
        {
            // 创建物体
            var playerPrefab = Resources.Load("LocalPlayer") as GameObject;
            var player = Object.Instantiate(playerPrefab, pos, Quaternion.identity);
            if (player == null)
            {
                Debug.Log("创建玩家失败");
                return;
            }

            player.transform.name = "Dwarf_local";

            // 在玩家列表中注册
            Globals.Instance.DataMgr.AllPlayers.Add(id, player);
            var pc = player.GetComponent<LocalDwarfController>();
            pc.currentPlayerId = id;
            pc.SetColor(color);
        }
        // 创建其他玩家
        else
        {
            var playerPrefab = Resources.Load("RemotePlayer") as GameObject;
            var cameraPrefab = Resources.Load("DwarfCameraRemote") as GameObject;

            var player = Object.Instantiate(playerPrefab, pos, Quaternion.identity);
            var camera = Object.Instantiate(cameraPrefab, pos, Quaternion.identity);

            if (player == null) Debug.Log("创建玩家失败");
            if (camera == null) Debug.Log("创建远程玩家相机失败");

            player.transform.name = "Dwarf_remote" + id;
            camera.transform.name = "DwarfCameraRemote" + id;

            // 在玩家列表中注册
            Globals.Instance.DataMgr.AllPlayers.Add(id, player);

            var pc = player.GetComponent<RemoteDwarfController>();
            pc.currentPlayerId = id;
            pc.localFrame = Globals.Instance.DataMgr.CurrentFrame;
            pc.serverFrame = Globals.Instance.DataMgr.CurrentFrame;
            pc.SetColor(color);
        }
    }

    // 移除玩家
    public void RemovePlayerResponse(int id)
    {
        Debug.LogFormat("RemovePlayer:{0}", id);

        if (Globals.Instance.DataMgr.AllPlayers.ContainsKey(id))
        {
            var player = Globals.Instance.DataMgr.AllPlayers[id];
            Globals.Instance.DataMgr.AllPlayers.Remove(id);
            Object.Destroy(player);
        }
    }

    // 处理其他客户端发来的操作
    public void ActionResponse(int id, int frame, int inputH, int inputV, int inputJump, int inputS, float fx, float fz)
    {
        // 检查玩家是否存在、是否是其他玩家
        if (Globals.Instance.DataMgr.AllPlayers.ContainsKey(id) && id != Globals.Instance.DataMgr.CurrentPlayerId)
        {
            // 将数据包转交给RemoteDwarfController脚本进行处理
            var player = Globals.Instance.DataMgr.AllPlayers[id];
            player.GetComponent<RemoteDwarfController>().AddRemoteAction(id, frame, inputH, inputV, inputJump, inputS, fx, fz);
        }
    }

    // 处理服务器定时发送的全局同步请求
    public void SyncInfoResponse(string info)
    {
        if (Globals.Instance.DataMgr.CurrentPlayerId == -1) return;
        if (!Globals.Instance.DataMgr.AllPlayers.ContainsKey(Globals.Instance.DataMgr.CurrentPlayerId)) return;

        //手动设置本机所有可上传的信息所在脚本的标志变量（isSyncAll）
        Globals.Instance.DataMgr.AllPlayers[Globals.Instance.DataMgr.CurrentPlayerId].GetComponent<LocalDwarfController>().isSyncAll = true;
    }

    // 处理其他玩家发来的状态数据
    public void SnapshotResponse(int id, int frame, double p1, double p2, double p3, double r1, double r2, double r3, double r4, double s1, double s2, double s3)
    {
        if (id == Globals.Instance.DataMgr.CurrentPlayerId)
        {
            return;
        }

        // 打包数据
        Vector3 pos = new Vector3((float)p1, (float)p2, (float)p3);
        Quaternion rot = new Quaternion((float)r1, (float)r2, (float)r3, (float)r4);
        Vector3 scl = new Vector3((float)s1, (float)s2, (float)s3);

        //处理已在线玩家的Snapshot
        if (Globals.Instance.DataMgr.AllPlayers.ContainsKey(id))
        {
            var player = Globals.Instance.DataMgr.AllPlayers[id];
            player.GetComponent<RemoteDwarfController>().HandleSnapshot(frame, pos, rot, scl);
        }
    }

    public void AddCoinResponse(int id, float x, float y, float z, int ownerPlayerId)
    {
        GameObject tempGo;
        if (Globals.Instance.DataMgr.AllCoins.TryGetValue(id, out tempGo))
        {
            if (null != tempGo)
            {
                return;
            }
            else
            {
                Globals.Instance.DataMgr.AllCoins.Remove(id);
            }
        }

        Vector3 pos = new Vector3(x, y, z);
        var coinPrefab = Resources.Load("Coin") as GameObject;
        var coinGo = Object.Instantiate(coinPrefab, pos, Quaternion.identity);

        coinGo.transform.name = "Coin" + id;

        var coin = coinGo.GetComponent<Coin>();
        coin.Init(id, ownerPlayerId);

        Globals.Instance.DataMgr.AllCoins.Add(id, coinGo);
    }

    public void RemoveCoinResponse(int id, int pickerPlayerId)
    {
        GameObject tempGo;
        if (Globals.Instance.DataMgr.AllCoins.TryGetValue(id, out tempGo))
        {
            Globals.Instance.DataMgr.AllCoins.Remove(id);

            if (null != tempGo)
            {
                Object.Destroy(tempGo);
            }
        }
    }

}