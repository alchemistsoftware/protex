const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("ProtexAPI", {
	GetScriptNames: () => ipcRenderer.invoke("get-script-names"),
    WriteConfig: (ConfigStr: string) => ipcRenderer.invoke("write-config", ConfigStr),
    WriteScript: (ScriptName: string, Src: string) => ipcRenderer.invoke(
        "write-script", ScriptName, Src),
    ReadScript: (ScriptName: string) => ipcRenderer.invoke(
        "read-script", ScriptName),
    RunExtractor: (ConfigName: string, Text: string) => ipcRenderer.invoke(
        "run-extractor", ConfigName, Text)
});
