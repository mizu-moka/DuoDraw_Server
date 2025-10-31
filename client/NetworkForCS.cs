using SLua;
using UnityEngine;
using System;
using System.Text;

public class NetworkForCS
{
    // 定义Lua函数
    private LuaSvr luaSvr;
    private LuaTable luaSelf;
    private LuaFunction luaUpdate;
    private LuaFunction luaConnectToServer;
    private LuaFunction luaSendPlayerInput;
    private LuaFunction luaSendClearRequest;
    private LuaFunction luaSendColorChangeRequest;
    private LuaFunction luaSendArtworkBase64;
    private LuaFunction luaRequestArtworkByIndex;

    public void Init()
    {
        // 启动本地Lua服务器
        luaSvr = new LuaSvr();

        // 在本地Lua服务器上注册函数
        luaSvr.init(null, OnComplete);
    }

    private void OnComplete()
    {
        luaSelf = (LuaTable)luaSvr.start("network");
        luaUpdate = (LuaFunction)luaSelf["update"];

        luaConnectToServer = (LuaFunction)luaSelf["connect_to_server"];
        luaSendPlayerInput = (LuaFunction)luaSelf["send_player_input"];
        luaSendClearRequest = (LuaFunction)luaSelf["send_clear_request"];
        luaSendColorChangeRequest = (LuaFunction)luaSelf["send_color_change_request"];
        luaSendArtworkBase64 = (LuaFunction)luaSelf["send_artwork_base64"];
        luaRequestArtworkByIndex = (LuaFunction)luaSelf["request_artwork_by_index"];
    }

    // Connect to server
    public void ConnectToServer()
    {
        luaConnectToServer.call(luaSelf);
        Debug.Log("Connecting to server...");
    }


    public void Tick(float dt)
    {
        luaUpdate.call(luaSelf);
    }

    /***
    // 初始化网络，在游戏启动时调用
    public void InitRequest()
    {
        luaSendInit.call(luaSelf, 0);
    }
    ***/

    // Send player input to server
    public void SendPlayerInput(int playerId, float x, float y, bool space)
    {
        luaSendPlayerInput.call(luaSelf, playerId, x, y, space);
        Debug.Log($"Sending input for player {playerId} - X: {x}, Y: {y}, Space: {space}");
    }

    // Request that server clear the canvas (server will broadcast to all clients)
    public void SendClearRequest(int playerId)
    {
        luaSendClearRequest.call(luaSelf, playerId);
        Debug.Log($"Sending clear request for player {playerId}");
    }

    public void SendColorChangeRequest(int playerId, int colorId)
    {
        luaSendColorChangeRequest.call(luaSelf, playerId, colorId);
        Debug.Log($"Sending color change request for player {playerId}, color {colorId}");
    }

    // Upload artwork bytes (will be base64-encoded and handed to Lua for chunking)
    public void SendArtwork(int playerId, string name, string author, byte[] bytes)
    {
        if (luaSendArtworkBase64 == null)
        {
            Debug.LogError("luaSendArtworkBase64 not bound");
            return;
        }
        string b64 = System.Convert.ToBase64String(bytes);
        luaSendArtworkBase64.call(luaSelf, playerId, name, author, b64);
        Debug.Log($"Sending artwork by {author}, size={bytes.Length}");
    }

    public void RequestArtworkByIndex(int index)
    {
        if (luaRequestArtworkByIndex == null)
        {
            Debug.LogError("luaRequestArtworkByIndex not bound");
            return;
        }
        luaRequestArtworkByIndex.call(luaSelf, index);
        Debug.Log($"Requesting artwork by index {index}");
    }
}
