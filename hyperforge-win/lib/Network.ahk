; Network.ahk — IP, hostname, reverse DNS, ARIN-style whois paste

RegisterNetworkHotkeys() {
    BindHyper("m", (*) => CopyHostname())
    ; L is Workspaces. Copy LAN IP from the command bar (or a {{lan-ip}} snippet).
    BindHyper("w", (*) => ArinWhois(), "send")

    ; Win+Ctrl+I. Win+I is Windows Settings and is not bound.
    Hotkey "#^i", (*) => ReverseDnsClipboard()
}

CopyHostname(*) {
    A_Clipboard := A_ComputerName
    ShowMsg("Copied " A_ComputerName)
}

CopyLanIP(*) {
    ip := LanIPAddress()
    if (ip = "") {
        ShowMsg("No LAN address")
        return
    }
    A_Clipboard := ip
    ShowMsg("Copied " ip)
}

; Only what ARIN whois serves goes out: IPv4 (optional /0-32), IPv6 (optional
; /0-128) or an AS number (AS12345). No domains or hostnames — dotted secrets and
; internal names would otherwise be POSTed to a third party.
LooksLikeWhoisQuery(s) {
    s := Trim(s)
    if (s = "" || StrLen(s) > 43 || RegExMatch(s, "\s"))
        return false
    if RegExMatch(s, "i)^AS\d{1,10}$")
        return Integer(SubStr(s, 3)) <= 4294967295
    prefix := ""
    if RegExMatch(s, "^(.+)/(\d{1,3})$", &m) {
        s := m[1], prefix := Integer(m[2])
    }
    if _isIPv4(s)
        return (prefix = "" || prefix <= 32)
    if _isIPv6(s)
        return (prefix = "" || prefix <= 128)
    return false
}

_isIPv4(s) {
    if !RegExMatch(s, "^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$", &m)
        return false
    Loop 4 {
        if (Integer(m[A_Index]) > 255)
            return false
    }
    return true
}

; Hex groups only (no embedded IPv4 tail, no %zone). At most one "::".
_isIPv6(s) {
    if (StrLen(s) < 2 || StrLen(s) > 39 || !RegExMatch(s, "i)^[0-9a-f:]+$"))
        return false
    halves := StrSplit(s, "::")
    if (halves.Length > 2)
        return false
    count := 0
    for half in halves {
        if (half = "")
            continue
        for g in StrSplit(half, ":") {
            if !RegExMatch(g, "i)^[0-9a-f]{1,4}$")
                return false
            count++
        }
    }
    return (halves.Length = 2) ? (count <= 7) : (count = 8)
}

ArinWhois(*) {
    url := HFConfig.Get("network.arin_whois", "https://whois.arin.net/ui/query.do")
    query := Trim(A_Clipboard)
    if !LooksLikeWhoisQuery(query) {
        ShowMsg("Whois: clipboard isn't an IP, CIDR or AS number — nothing sent")
        return
    }
    post := "queryinput=" UrlEncode(query)
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

ReverseDnsClipboard(*) {
    ip := Trim(A_Clipboard)
    try {
        results := ReverseLookup(ip)
        A_Clipboard := results
        MsgBox results, "Reverse DNS"
    } catch as e {
        MsgBox "Lookup failed: " e.Message
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
