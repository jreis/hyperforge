; Network.ahk — IP, hostname, reverse DNS, ARIN-style whois paste

RegisterNetworkHotkeys() {
    HotIf HyperAllowed
    Hotkey "#^!+m", (*) => {
        A_Clipboard := A_ComputerName
        ShowMsg("Copied " A_ComputerName)
    }
    Hotkey "#^!+w", (*) => {
        url := HFConfig.Get("network.arin_whois", "https://whois.arin.net/ui/query.do")
        post := "queryinput=" A_Clipboard
        try {
            http := ComObject("MSXML2.ServerXMLHTTP.6.0")
            http.open("POST", url, false)
            http.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
            http.send(post)
            whoisXml := http.responseXML
            A_Clipboard := http.responseText
            try {
                namespace := "xmlns:ns='https://www.arin.net/whoisrws/core/v1'"
                whoisXml.setProperty("SelectionNamespaces", namespace)
                result := whoisXml.selectSingleNode("//ns:name").text
                ShowMsg(result)
            } catch {
                ShowMsg("Whois response on clipboard")
            }
        } catch {
            ShowMsg("Whois failed")
        }
    }
    HotIf

    ; Non-Hyper (Win+I variants) — always on
    Hotkey "#i", (*) => {
        addrs := SysGetIPAddresses()
        if addrs.Length {
            A_Clipboard := addrs[1]
            ShowMsg("Copied " addrs[1])
        }
    }
    Hotkey "#^i", (*) => {
        ip := Trim(A_Clipboard)
        try {
            results := ReverseLookup(ip)
            A_Clipboard := results
            MsgBox results, "Reverse DNS"
        } catch as e {
            MsgBox "Lookup failed: " e.Message
        }
    }
}

ReverseLookup(IPAddr) {
    static WSA_SUCCESS := 0, INADDR_ANY := 0x00000000, INADDR_NONE := 0xffffffff
    static NI_MAXHOST := 1025, AF_INET := 2
    WSADATA := Buffer(394 + (A_PtrSize - 2) + A_PtrSize)
    if (DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", WSADATA) != WSA_SUCCESS)
        throw OSError(DllCall("ws2_32\WSAGetLastError"))
    inaddr := DllCall("ws2_32\inet_addr", "AStr", IPAddr, "UInt")
    if (inaddr = INADDR_ANY) || (inaddr = INADDR_NONE) {
        DllCall("ws2_32\WSACleanup")
        throw Error("Invalid address")
    }
    Sockaddr := Buffer(16)
    NumPut("Short", AF_INET, Sockaddr, 0)
    NumPut("UInt", inaddr, Sockaddr, 4)
    HostName := Buffer(NI_MAXHOST << 1, 0)
    if (DllCall("ws2_32\GetNameInfoW", "Ptr", Sockaddr, "UInt", Sockaddr.Size, "Ptr", HostName,
        "UInt", NI_MAXHOST, "Ptr", 0, "UInt", 0, "Int", 0) != WSA_SUCCESS) {
        DllCall("ws2_32\WSACleanup")
        throw OSError(DllCall("ws2_32\WSAGetLastError"))
    }
    DllCall("ws2_32\WSACleanup")
    return StrGet(HostName)
}
