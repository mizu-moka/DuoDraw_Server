using UnityEngine;
using UnityEngine.SceneManagement;
using SLua;

// 管理器

[CustomLuaClass]
public class Globals : MonoBehaviour
{
    public NetworkForCS NetworkForCS = new NetworkForCS();
    public NetworkForLua NetworkForLua = new NetworkForLua();
    public DataMgr DataMgr = new DataMgr();

    private int m_currentSceneId = -1;
    private bool m_sceneLoaded;


    public static Globals Instance
    {
        get;
        private set;
    }

    void Awake()
    {
        Application.targetFrameRate = 50;

        Instance = this;

        DontDestroyOnLoad(gameObject);

        NetworkForCS.Init();
        
        SceneManager.sceneLoaded += OnSceneLoaded;
    }
    
    // 通过场景ID，加载场景
    public void LoadScene(int sceneId)
    {
        if (m_currentSceneId != sceneId)
        {
            m_sceneLoaded = false;
            SceneManager.LoadScene("Game", LoadSceneMode.Single);
            m_currentSceneId = sceneId;
        }
    }

    void OnSceneLoaded(Scene scene, LoadSceneMode mode)
    {
        Debug.Log("场景已加载： " + scene.name);
        m_sceneLoaded = true;
    }

    public bool IsSceneLoaded(int sceneId)
    {
        return m_currentSceneId == sceneId && m_sceneLoaded;
    }

    // Lua服务器每帧更新
    void Update()
    {
        float dt = Time.deltaTime;
        NetworkForCS.Tick(dt);
    }
}