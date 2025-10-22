using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class DropCoinButton : MonoBehaviour
{
    public void OnBtnClick()
    {
        GameObject localPlayerGo;
        if (Globals.Instance.DataMgr.AllPlayers.TryGetValue(Globals.Instance.DataMgr.CurrentPlayerId, out localPlayerGo))
        {
            if (null != localPlayerGo)
            {
                Globals.Instance.NetworkForCS.AddCoinReq(localPlayerGo.transform.position);
            }
        }
    }

    public void Update()
    {
        if (Input.GetKeyDown(KeyCode.F))
        {
            OnBtnClick();
        }
    }
}
