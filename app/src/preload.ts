const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("ElectronAPI", {
	GetPyIncludePath: () => ipcRenderer.invoke("get-py-include-path"),
    WriteConfig: (ConfigStr: string) => ipcRenderer.invoke("write-config", ConfigStr),
    RunExtractor: (ConfigName: string, Text: string) => ipcRenderer.invoke(
        "run-extractor", ConfigName, Text)

});
