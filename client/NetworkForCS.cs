using SLua;
using UnityEngine;

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
}
