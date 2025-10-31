using UnityEngine;
using UnityEngine.UI;
using System.Collections;
using System;

public class RegionCapture : MonoBehaviour
{
    [Header("截图区域（UI 或 世界坐标区域的 RectTransform）")]
    public RectTransform targetRegion;

    [Header("显示截图结果的 UI Image")]
    public Image displayImage;

    // 暂存的截图字节数组
    private byte[] capturedBytes;
    [Header("Network Interface")]
    public NetworkForCS networkForCS;
    // Optional: assign a NetworkForLua instance (in inspector or via code) to receive artwork callbacks
    [Header("Lua Network Interface")]
    public NetworkForLua networkForLua;

    // =============================
    // 按钮1：截图 -> bytes
    // =============================
    public void CaptureRegionToBytes()
    {
        StartCoroutine(CaptureCoroutine());
    }

    private IEnumerator CaptureCoroutine()
    {
        // 等待渲染结束（必须，否则会截到空图）
        yield return new WaitForEndOfFrame();

        // 将 RectTransform 转换为屏幕像素坐标
        Vector3[] corners = new Vector3[4];
        targetRegion.GetWorldCorners(corners);
        // 左下角在屏幕坐标中的位置
        Vector3 bottomLeft = corners[0];
        Vector3 topRight = corners[2];

        // 计算像素区域
        int x = Mathf.RoundToInt(bottomLeft.x);
        int y = Mathf.RoundToInt(bottomLeft.y);
        int width = Mathf.RoundToInt(topRight.x - bottomLeft.x);
        int height = Mathf.RoundToInt(topRight.y - bottomLeft.y);

        // 安全检查
        if (width <= 0 || height <= 0)
        {
            Debug.LogError("[RegionCapture] 截图区域无效，宽高应大于0");
            yield break;
        }

        // 创建Texture并读取屏幕像素
        Texture2D tex = new Texture2D(width, height, TextureFormat.RGBA32, false);
        tex.ReadPixels(new Rect(x, y, width, height), 0, 0);
        tex.Apply();

        // 编码为PNG字节
        capturedBytes = tex.EncodeToPNG();
        Destroy(tex);

        // 输出大小
        Debug.Log($"[RegionCapture] 截图完成，byte大小: {capturedBytes.Length} 字节");

        UploadCapturedRegion("CapturedRegion", "Player", Globals.Instance.DataMgr.CurrentPlayerId);
    }

    // =============================
    // 按钮2：显示 bytes -> Image
    // =============================
    public void ShowBytesOnImage()
    {
        if (capturedBytes == null || capturedBytes.Length == 0)
        {
            Debug.LogError("[RegionCapture] 尚未截图或截图数据为空");
            return;
        }

        // 从byte创建Texture
        Texture2D tex = new Texture2D(2, 2, TextureFormat.RGBA32, false);
        tex.LoadImage(capturedBytes);

        // 创建Sprite
        Sprite sprite = Sprite.Create(tex, new Rect(0, 0, tex.width, tex.height), new Vector2(0.5f, 0.5f));
        displayImage.sprite = sprite;

        Debug.Log($"[RegionCapture] 已显示截图，大小: {tex.width}x{tex.height}");
    }

    // Subscribe/unsubscribe to artwork events from NetworkForLua
    private void OnEnable()
    {
        if (networkForLua != null)
        {
            networkForLua.OnArtworkReceived += OnArtworkReceived;
        }
    }

    private void OnDisable()
    {
        if (networkForLua != null)
        {
            networkForLua.OnArtworkReceived -= OnArtworkReceived;
        }
    }

    // Handler for artwork received from NetworkForLua (base64 payload)
    private void OnArtworkReceived(string id, string name, string author, string base64Data, long time)
    {
        if (string.IsNullOrEmpty(base64Data))
        {
            Debug.LogError("[RegionCapture] ArtworkReceived but base64Data is empty or null");
            return;
        }

        byte[] bytes = null;
        try
        {
            bytes = Convert.FromBase64String(base64Data);
        }
        catch (Exception e)
        {
            Debug.LogError($"[RegionCapture] Failed to decode base64 artwork: {e}");
            return;
        }

        // Create texture and sprite (mirrors ShowBytesOnImage)
        Texture2D tex = new Texture2D(2, 2, TextureFormat.RGBA32, false);
        bool ok = tex.LoadImage(bytes);
        if (!ok)
        {
            Debug.LogError("[RegionCapture] tex.LoadImage failed for artwork bytes");
            return;
        }

        Sprite sprite = Sprite.Create(tex, new Rect(0, 0, tex.width, tex.height), new Vector2(0.5f, 0.5f));
        displayImage.sprite = sprite;
        Debug.Log($"[RegionCapture] Artwork displayed id={id} name={name} author={author} time={time} size={tex.width}x{tex.height}");
    }

    // Upload captured bytes to server via NetworkForCS
    public void UploadCapturedRegion(string name, string author, int playerId)
    {
        if (capturedBytes == null || capturedBytes.Length == 0)
        {
            Debug.LogError("[RegionCapture] no captured bytes to upload");
            return;
        }
        if (networkForCS == null)
        {
            Debug.LogError("[RegionCapture] networkForCS not set");
            return;
        }
        networkForCS.SendArtwork(playerId, name, author, capturedBytes);
        Debug.Log($"[RegionCapture] Uploading artwork name={name} size={capturedBytes.Length}");
    }
}
