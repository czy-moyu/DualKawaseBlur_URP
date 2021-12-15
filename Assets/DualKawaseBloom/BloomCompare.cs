using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class BloomCompare : MonoBehaviour
{
    [SerializeField]
    private DualKawaseBloom _bloom;
    [SerializeField]
    private Volume _volume;
    private bool myBloom = true;

    private void OnGUI()
    {
        myBloom = GUI.Toggle(new Rect(30, 30, 1000, 500), myBloom, "切换bloom");
        _bloom.SetActive(myBloom);
        var volumeComponents = _volume.profile.components;
        foreach (var component in volumeComponents)
        {
            if (component.name.Contains("Bloom"))
            {
                component.active = !myBloom;
                break;
            }
        }
    }
}
