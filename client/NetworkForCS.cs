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

    // private LuaFunction luaSendArtworkBase64;
    // private LuaFunction luaSendArtworkFromPath;
    // private LuaFunction luaReceiveArtworkB64Chunk;
    private LuaFunction luaUploadStartFromCS;
    private LuaFunction luaUploadChunkFromCS;

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

        // luaSendArtworkBase64 = (LuaFunction)luaSelf["send_artwork_base64"];
        // luaSendArtworkFromPath = (LuaFunction)luaSelf["send_artwork_from_path"];
        // luaReceiveArtworkB64Chunk = (LuaFunction)luaSelf["receive_artwork_b64_chunk"];

        luaUploadStartFromCS = (LuaFunction)luaSelf["upload_start_from_cs"];
        luaUploadChunkFromCS = (LuaFunction)luaSelf["upload_chunk_from_cs"];
        luaRequestArtworkByIndex = (LuaFunction)luaSelf["request_artwork_by_index"];
        // subscribe to UploadAck events from the managed NetworkForLua (if available) so we can send queued chunks
        try
        {
            var nl = Globals.Instance.NetworkForLua;
            if (nl != null)
            {
                nl.OnUploadAck += OnUploadAckHandler;
            }
        }
        catch (Exception ex)
        {
            Debug.LogWarning("NetworkForCS: failed to subscribe to NetworkForLua.OnUploadAck: " + ex);
        }
    }

    // pending uploads keyed by client token
    private System.Collections.Generic.Dictionary<string, System.Collections.Generic.List<string>> pendingChunks = new System.Collections.Generic.Dictionary<string, System.Collections.Generic.List<string>>();
    private class UploadMeta { public int playerId; public string name; public string author; public int totalChunks; public UploadMeta(int p, string n, string a, int t) { playerId = p; name = n; author = a; totalChunks = t; } }
    private System.Collections.Generic.Dictionary<string, UploadMeta> pendingMeta = new System.Collections.Generic.Dictionary<string, UploadMeta>();

    // Handler for UploadAck events from NetworkForLua (subscribe externally after init)
    public void OnUploadAckHandler(string id, bool success, string message, string clientToken)
    {
        if (string.IsNullOrEmpty(clientToken)) return;
        if (!pendingChunks.ContainsKey(clientToken)) return;
        if (!success)
        {
            Debug.LogError($"Upload start failed for token={clientToken}: {message}");
            pendingChunks.Remove(clientToken);
            pendingMeta.Remove(clientToken);
            return;
        }
        // found pending chunks, send them to Lua using the server-assigned id
        var parts = pendingChunks[clientToken];
        var meta = pendingMeta[clientToken];
        int total = meta.totalChunks;
        for (int i = 0; i < parts.Count; i++)
        {
            int idx = i + 1;
            try
            {
                if (luaUploadChunkFromCS != null)
                {
                    luaUploadChunkFromCS.call(luaSelf, id, meta.name, meta.author, idx, total, parts[i]);
                }
            }
            catch (Exception ex)
            {
                Debug.LogError("Error sending chunk to Lua: " + ex);
            }
        }
        pendingChunks.Remove(clientToken);
    pendingMeta.Remove(clientToken);
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

     // Upload artwork bytes
    public void SendArtwork(int playerId, string name, string author, byte[] bytes)
    {
        Debug.Log("[NetworkForCS] SendArtwork");
        // Single flow: C# splits bytes into chunks, calls upload_start_from_cs, then waits for start ack and sends chunks
        if (luaUploadStartFromCS == null || luaUploadChunkFromCS == null)
        {
            Debug.LogError("Lua upload functions not bound (upload_start_from_cs/upload_chunk_from_cs)");
            return;
        }

        int chunkSize = 60000;
        int len = bytes.Length;
        int total = (len + chunkSize - 1) / chunkSize;
        if (total < 1) total = 1;

        string clientToken = $"{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}_{UnityEngine.Random.Range(0,999999)}";

        var parts = new System.Collections.Generic.List<string>(total);
        for (int i = 0; i < total; i++)
        {
            int s = i * chunkSize;
            int count = Math.Min(chunkSize, len - s);
            byte[] partBytes = new byte[count];
            System.Array.Copy(bytes, s, partBytes, 0, count);
            string partB64 = System.Convert.ToBase64String(partBytes);
            parts.Add(partB64);
        }

        pendingChunks[clientToken] = parts;
        pendingMeta[clientToken] = new UploadMeta(playerId, name, author, total);

        // send start; when server replies with art_upload_ack containing client_token, OnUploadAckHandler will send chunks
        try
        {
            // SLua can fail when passing non-ANSI characters in plain strings on some platforms.
            // Encode name/author as base64 (ASCII-safe) before sending to Lua; Lua will decode.
            string nameB64 = string.IsNullOrEmpty(name) ? "" : System.Convert.ToBase64String(Encoding.UTF8.GetBytes(name));
            string authorB64 = string.IsNullOrEmpty(author) ? "" : System.Convert.ToBase64String(Encoding.UTF8.GetBytes(author));
            luaUploadStartFromCS.call(luaSelf, playerId, nameB64, authorB64, total, clientToken);
        }
        catch (Exception ex)
        {
            Debug.LogError("Failed to call luaUploadStartFromCS: " + ex);
            pendingChunks.Remove(clientToken);
            pendingMeta.Remove(clientToken);
        }
        Debug.Log($"Queued {total} chunks for upload (token={clientToken}) size={bytes.Length}");
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
