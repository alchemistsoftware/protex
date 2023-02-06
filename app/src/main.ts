// TODO(cjb): export this in a common.ts file somewhere.
interface py_include_path_and_entries
{
    PyIncludePath: string,
    Entries: string[],
}

//TODO(cjb): Pass data dir as sys arg

const { app, BrowserWindow, ipcMain } = require("electron");
const { spawn, spawnSync } = require("node:child_process");
const path = require("path");
const fs = require("fs");

ipcMain.handle("get-py-include-path", async (Event: any) =>
{
    console.log("<<<\nget-py-include-path");

    let Result: py_include_path_and_entries = {
        PyIncludePath: "plugins",
        Entries: [],
    };

    return new Promise((Resolve) =>
    {
        fs.readdir("./data/plugins", (Err: Error, Files: string[]) =>
        {
            if (Err) throw Err;
            Result.Entries = Files.slice(0);

            console.log(">>>");
            console.log(Result);

            Resolve(Result);
        });
    });
});

ipcMain.handle("run-extractor", async (Event: any, ConfName: string, Text: string) =>
{
    return new Promise<any>((Resolve) =>
    {
        console.log("<<<\nrun-extractor");

        const Packager = spawn("./bin/packager", ["./data/" + ConfName, "./data/gracie.bin"]);
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

            const ExtractorProcess = spawnSync("./bin/capi_io", ["./data/gracie.bin"],
                                                  {"input":Text});

            if (ExtractorProcess.status !== 0)
            {
                throw "Extractor fail";
            }
            console.log(">>>\n");
            console.log(ExtractorProcess.stderr.toString());
            console.log(ExtractorProcess.stdout.toString());

            Resolve(ExtractorProcess.stdout.toString());
        });


    });
});

ipcMain.handle("write-config", async (Event: any, ConfigStr: string) =>
{
    console.log("<<<\nwrite-config");

    return new Promise<void>((Resolve) =>
    {
        const Config = JSON.parse(ConfigStr);

        const Bytes = new Uint8Array(Buffer.from(ConfigStr));
        fs.writeFile("./data/" + Config.ConfName, Bytes, (Err: Error) =>
        {
            if (Err) throw Err;

            console.log("Done writing ./data/" + Config.ConfName);
            Resolve();
        });
    });
});

const createWindow = () =>
{
    const win = new BrowserWindow({
        width: 800,
        height: 600,
        webPreferences: {
            preload: path.join(__dirname, "preload.js")
        }
    });

    win.loadFile("../index.html");
}

app.whenReady().then(() =>
{
    createWindow();
})
