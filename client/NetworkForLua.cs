using SLua;
using UnityEngine;

[CustomLuaClass]
public class NetworkForLua
{
    // Called when the server confirms connection
    public void RecvConnectOK(int playerId)
    {
        Debug.Log("Connected to server successfully. Assigned Player ID: " + playerId);
        Globals.Instance.DataMgr.CurrentPlayerId = playerIdId;
        if (id != -1)
        {
            Debug.Log("登陆成功。本机用户 ID = " + Globals.Instance.DataMgr.CurrentPlayerId);
        }
        else // （原理上来说，目前不会出现。之后可能修改房间满员逻辑？）
        {
            Debug.Log("已满员，登陆失败。请关闭客户端并重试");
        }
    }

    // Updates pencil state
    public void UpdatePencil(float x, float y, bool drawing)
    {
        Debug.Log($"Pencil updated - X: {x}, Y: {y}, Drawing: {drawing}");
    }

    // Clears the canvas
    public void ClearCanvas()
    {
        Debug.Log("Canvas cleared.");
    }

    // Called when the game starts
    public void OnStartGame(string[] players)
    {
        Debug.Log("Game started with players: " + string.Join(", ", players));
    }

    // Called when the game is paused
    public void OnGamePause(string reason)
    {
        Debug.Log("Game paused. Reason: " + reason);
    }
}