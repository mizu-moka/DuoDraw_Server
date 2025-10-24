using SLua;
using UnityEngine;

public class NetworkForCS
{
    // 定义Lua函数
    private LuaSvr luaSvr;
    private LuaTable luaSelf;
    private LuaFunction luaConnectToServer;
    private LuaFunction luaSendPlayerInput;

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

        luaConnectToServer = (LuaFunction)luaSelf["connect_to_server"];
        luaSendPlayerInput = (LuaFunction)luaSelf["send_player_input"];
    }

    // Connect to server
    public void ConnectToServer()
    {
        luaConnectToServer.call(luaSelf);
        Debug.Log("Connecting to server...");
    }

    
    /***
    public void Tick(float dt)
    {
        luaUpdate.call(luaSelf);
    }
    // 初始化网络，在游戏启动时调用
    public void InitRequest()
    {
        luaSendInit.call(luaSelf, 0);
    }
    ***/

    // Send player input to server
    public void SendPlayerInput(int playerId, float x, float y, bool space, bool clear)
    {
        luaSendPlayerInput.call(luaSelf, playerId, x, y, space, clear);
        Debug.Log($"Sending input for player {playerId} - X: {x}, Y: {y}, Space: {space}, Clear: {clear}");
    }
}
