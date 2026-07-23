; Config.ahk — load config.ini (with defaults)

class HFConfig {
    static file := ""
    static data := Map()

    static Init(scriptDir) {
        HFConfig.file := scriptDir "\config.ini"
        example := scriptDir "\config.example.ini"
        if !FileExist(HFConfig.file) && FileExist(example) {
            try FileCopy(example, HFConfig.file)
        }
        HFConfig.data := Map()
        if FileExist(HFConfig.file) {
            HFConfig._loadIni(HFConfig.file)
        }
    }

    static _loadIni(path) {
        section := ""
        Loop Read path {
            line := Trim(A_LoopReadLine)
            if (line = "" || SubStr(line, 1, 1) = ";")
                continue
            if RegExMatch(line, "^\[(.+)\]$", &m) {
                section := m[1]
                continue
            }
            if RegExMatch(line, "^([^=]+)=(.*)$", &m) {
                key := section "." Trim(m[1])
                HFConfig.data[key] := Trim(m[2])
            }
        }
    }

    static Get(key, default := "") {
        if HFConfig.data.Has(key) {
            v := HFConfig.data[key]
            return (v = "") ? default : v
        }
        return default
    }

    static GetBool(key, default := true) {
        v := HFConfig.Get(key, default ? "1" : "0")
        return (v = "1" || v = "true" || v = "yes")
    }

    static GetInt(key, default := 0) {
        v := HFConfig.Get(key, default)
        return Integer(v)
    }

    static Path(name, fallback := "") {
        p := HFConfig.Get("paths." name, "")
        return (p != "") ? p : fallback
    }
}
