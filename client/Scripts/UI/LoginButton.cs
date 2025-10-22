using System;
using UnityEngine.UI;
using UnityEngine;

public class LoginButton : MonoBehaviour
{
    public InputField InputName;
    public InputField InputPassword;

    // 在游戏启动时，向服务器发送任意一条消息，来建立与服务器的连接
    private void Start()
    {
        //Globals.Instance.NetworkForCS.InitRequest();
    }

    // 向服务器发送登录请求
    public void Login()
    {
        string playerName = InputName.text;
        string playerPassword = InputPassword.text;
        int color = GetColor(playerName);
        Globals.Instance.NetworkForCS.LoginRequest(playerName, playerPassword, color);

        Debug.Log("正在登录...btn");
    }

    public void Connect()
    {
        Globals.Instance.NetworkForCS.ConnectToServer();
    }

    private static int GetColor(string name)
    {
        return name.GetHashCode();
    }
}