using SLua;
using UnityEngine;
using System;

[CustomLuaClass]
public class NetworkForLua
{


    // Receives connectionOk from server
    public event Action OnConnectOK;
    
    public void RecvConnectOK(int playerId)
    {
        Debug.Log("Connected to server successfully. Assigned Player ID: " + playerId);
        Globals.Instance.DataMgr.CurrentPlayerId = playerId;
        if (playerId != -1)
        {
            Debug.Log("登陆成功。本机用户 ID = " + Globals.Instance.DataMgr.CurrentPlayerId);
            // 连接成功时触发事件
            OnConnectOK?.Invoke();
        }
        else // （原理上来说，目前不会出现。之后可能修改房间满员逻辑？）
        {
            Debug.Log("已满员，登陆失败。请关闭客户端并重试");
        }
    }

    // Receives game start notification from server
    public event Action OnGameStart;
    public void StartGame(string[] players)
    {
        Debug.Log("Game started with players: " + string.Join(", ", players));
        OnGameStart?.Invoke();
    }

    // Updates pencil state (now includes toggle1/toggle2 values)
    // Parameters: x, y, drawing, toggle1, toggle2
    public event Action<float, float, bool, bool, bool> OnRecvUpdatePencil;
    public event Action<bool> OnToggleDrawing;
    private bool prevDrawing = false;
    public void UpdatePencil(float x, float y, bool drawing, bool toggle1, bool toggle2)
    {
        Debug.Log($"Pencil updated - X: {x}, Y: {y}, Drawing: {drawing}, Toggle1: {toggle1}, Toggle2: {toggle2}");
        // 触发事件 (x, y, drawing, toggle1, toggle2)
        OnRecvUpdatePencil?.Invoke(x, y, drawing, toggle1, toggle2);

        // 触发切换事件 when drawing state changes
        if (drawing != prevDrawing)
        {
            OnToggleDrawing?.Invoke(drawing);
            prevDrawing = drawing;
        }
    }

    // Clears the canvas
    public event Action OnClearCanvas;
    public void ClearCanvas()
    {
        Debug.Log("Canvas cleared.");
        OnClearCanvas?.Invoke();
    }

    // Receive color change broadcast from server (includes originating player_id)
    public event Action<int, int> OnColorChanged;
    public void ColorChanged(int playerId, int colorId)
    {
        Debug.Log($"Color changed by player {playerId} to id: {colorId}");
        OnColorChanged?.Invoke(playerId, colorId);
    }

    // Upload acknowledgement from server. Includes optional clientToken for start acks.
    public event Action<string, bool, string, string> OnUploadAck;
    public void UploadAck(string id, bool success, string message, string clientToken)
    {
        Debug.Log($"Upload ack for {id}: success={success} message={message} clientToken={clientToken}");
        OnUploadAck?.Invoke(id, success, message, clientToken);
    }

    // Artwork received (base64), time is unix timestamp
    public event Action<string, string, string, string, long> OnArtworkReceived;
    public void ArtworkReceived(string id, string name, string author, string base64Data, long time)
    {
        Debug.Log($"Artwork received id={id} name={name} author={author} time={time} size_b64={(base64Data != null ? base64Data.Length : 0)}");
        OnArtworkReceived?.Invoke(id, name, author, base64Data, time);
    }

    // Called when a requested artwork (by id or index) was not found on server
    public event Action<string, string> OnArtworkNotFound;
    public void ArtworkNotFound(string id, string reason)
    {
        Debug.Log($"Artwork not found id={id} reason={reason}");
        OnArtworkNotFound?.Invoke(id, reason);
    }


    // Called when the game is paused
    public event Action<string> OnGamePauseEvent;
    public void OnGamePause(string reason)
    {
        Debug.Log("Game paused. Reason: " + reason);
        OnGamePauseEvent?.Invoke(reason);
    }
}