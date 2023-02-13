// TODO(cjb): export this in a common.ts file somewhere.
interface py_include_path_and_entries
{
    PyIncludePath: string,
    Entries: string[],
}

import process = require("node:process");

const { spawn, spawnSync } = require("node:child_process");
const electron = require("electron");
const path = require("path");
const fs = require("fs");

//TODO(cjb): Read data from config file?

let DataPath = "../data";
let BinPath = "../bin";
let ConfRelPluginsPath = "plugins";

// Tell main process how it should treat uncaught exceptions.

process.on('uncaughtException', (Err: any) =>
{
    console.log(Err);
});

electron.ipcMain.handle("get-py-include-path", async (Event: any) =>
{
    console.log("<<<\nget-py-include-path");

    let Result: py_include_path_and_entries = {
        PyIncludePath: ConfRelPluginsPath, // TODO(cjb): Hide this from user??
        Entries: [],
    };

    return new Promise((Resolve) =>
    {
        fs.readdir(`${DataPath}/${ConfRelPluginsPath}`, (Err: Error, Files: string[]) =>
        {
            if (Err) throw Err;
            Result.Entries = Files.slice(0);

            console.log(">>>");
            console.log(Result);

            Resolve(Result);
        });
    });
});

electron.ipcMain.handle(
    "run-extractor", async (Event: any, ConfName: string, Text: string) =>
{
    return new Promise<any>((Resolve) =>
    {
        console.log("<<<\nrun-extractor");

        const ArtiOutPath = `${DataPath}/` + path.parse(ConfName).name + '.bin';
        console.log(ArtiOutPath);
        const Packager = spawn(`${BinPath}/packager`, [`${DataPath}/${ConfName}`, ArtiOutPath]);
        Packager.stdout.on("data", (Out: Buffer | string) =>
        {
            console.log(Out.toString());
        });

        Packager.stderr.on("data", (Out: Buffer | string) =>
        {
            console.log(Out.toString());
        });

        Packager.on("close", (Status: number | null) =>
        {
            if (Status !== 0)
            {
                throw "Packager fail"
            }

            const ExtractorProcess = spawnSync(
                `${BinPath}/capi_io`, [ArtiOutPath], {"input":Text});

            console.log(">>>\n");
            console.log(ExtractorProcess.stderr.toString());
            console.log(ExtractorProcess.stdout.toString());
            if (ExtractorProcess.status !== 0)
            {
                throw "Extractor fail";
            }

            Resolve(ExtractorProcess.stdout.toString());
        });


    });
});

electron.ipcMain.handle("write-config", async (Event: any, ConfigStr: string) =>
{
    console.log("<<<\nwrite-config");

    return new Promise<void>((Resolve) =>
    {
        const Config = JSON.parse(ConfigStr);

        const Bytes = new Uint8Array(Buffer.from(ConfigStr));
        fs.writeFile(`${DataPath}/${Config.ConfName}`, Bytes, (Err: Error) =>
        {
            if (Err) throw Err;
            console.log(`Done writing ${DataPath}/${Config.ConfName}`);
            Resolve();
        });
    });
});

const CreateWindow = () =>
{

    // Query primary display to find min width/height

    const Display = electron.screen.getPrimaryDisplay();
    const MinWidth = Math.floor(Display.size.width / 3);
    const MinHeight = Math.floor(Display.size.height / 3)

    const Win = new electron.BrowserWindow({
        autoHideMenuBar: true,
        width: MinWidth,
        height: MinHeight,
        webPreferences: {
            preload: path.join(__dirname, "preload.js")
        }
    });
    Win.setMinimumSize(MinWidth, MinHeight);

    Win.loadFile(path.join(__dirname, "../index.html"));
}

electron.app.whenReady().then(() =>
{
    CreateWindow();
})
