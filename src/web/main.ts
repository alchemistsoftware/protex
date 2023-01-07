const SCPFontPath = "./assets/static/SourceCodePro-Regular.ttf";
const SCPFontSize = 0;

// Register Init and call on window load.
window.onload = () => Init();

function Init(): void
{
    // Get canvas element
    const Can = document.getElementById("canvas") as HTMLCanvasElement | null;
    if (Can == null)
    {
        throw "Couldn't get canvas element";
    }

    // Set canvas width/height
	const Dpr = window.devicePixelRatio;
    Can.width = Math.floor(window.innerWidth * Dpr);
    Can.height = Math.floor(window.innerHeight * Dpr);
    Can.style.width = window.innerWidth + "px";
    Can.style.height = window.innerHeight + "px";

    // Get canvas's rendering context
	const Ctx = Can.getContext("2d") as CanvasRenderingContext2D | null;
    if(Ctx == null)
    {
        throw "Couldn't get CanvasRenderingContext2D";
    }

    // Normalize coord system to css pixels
    Ctx.scale(Dpr, Dpr);

    Setup(Ctx);
    setInterval(Run, 33, Ctx);
}

/// Does various "setup-ee" things
function Setup(Ctx: CanvasRenderingContext2D): void
{
    // Fetch the font from assets
    let SCPFont = new FontFace("Source Code Pro", `url(${SCPFontPath})`);

    // Add to FontFaceSet
    document.fonts.add(SCPFont);

    // Load the font
    SCPFont.load().then(() =>
    {
        // This is broken...
        Ctx.font = `${SCPFontSize}px ${SCPFont.family}`;
        Ctx.fillStyle = "black";
    },
    (Err) => // Couldn't load font for whatever reason
    {
        throw Err;
    });
}

function Run(Ctx: CanvasRenderingContext2D): void
{
    let CanW = Ctx.canvas.width;
    let CanH = Ctx.canvas.height;

    const Text = "Prep Cooks/Cooks Starting at $25 an Hour Qualifications\n    Restaurant: 1 year (Required)\n    Work authorization (Required)\n    High school or equivalent (Preferred)\nBenefits\n\Pulled from the full job description\n\Employee discount\n\Paid time off\n\Full Job Description\nCooks\nGreat Opportunity to work at a new all-seasons resort in Northern Catskills - Wylder Windham Hotel.\nWe are looking for a dedicated, passionate, and skilled person to become a part of our pre-opening kitchen team for our Babbler's Restaurant. Our four-season resort will offer 110 hotel rooms, 1 restaurant, 1 Bakery with 20 acres of land alongside the Batavia Kill River, our family-friendly, all-season resort is filled with endless opportunities. This newly reimagined property offers banquet, wedding, and event facilities. We are looking for someone who is both willing to roll up their sleeves and work hard and has a desire to produce a first-class experience for our guests. Looking for applicants who are positive, upbeat, team-oriented, and a people person.\nWylder is an ever growing hotel brand with locations in Lake Tahoe, California and Tilghman Maryland.\nLots of room for upward growth within the company at the Wylder Windham property and Beyond.\nYoung at heart, active, ambitious individuals encouraged to apply!\nMust work weekends, nights, holidays and be flexible with schedule. Must be able to lift 50 pounds and work a physical Labor Job.\nWylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family-friendly in all aspects!.\nWylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family friendly in all aspects!\nCompetitive Pay- starting at $25-$26+ per hour based on experience\nJob Type: Full-time/Part-Time\nJob Type: Full-time\nPay: From $25-$26+ per hour based on experience\nBenefits:\n    Employee discount\n\    Paid time off\nSchedule:\n    10 hour shift\n\    8 hour shift\n\    Every weekend\n\    Holidays\n\    Monday to Friday\n\    Weekend availability\nEducation:\n    High school or equivalent (Preferred)\nExperience:\n    cooking: 1 year (Preferred)\nWork Location: One location\nJob Type: Full-time\nPay: $25.00 - $26.00 per hour\nBenefits:\n    Employee discount\n\    Paid time off\nPhysical setting:\n    Casual dining restaurant\nSchedule:\n    8 hour shift\n\    Day shift\n\    Holidays\n\    Monday to Friday\n\    Night shift\n\    Weekend availability\nEducation:\n    High school or equivalent (Preferred)\nExperience:\n    Restaurant: 1 year (Required)";

    let Dim = Ctx.measureText(Text[0]);
    let X = 0;
    let Y = Dim.actualBoundingBoxAscent;
    const Pad = Dim.width / 4

    // Handle drawing some text char by char
    for (let CharacterIndex = 0;
         CharacterIndex < Text.length;
         ++CharacterIndex)
     {
         Dim = Ctx.measureText(Text[CharacterIndex]);
         if (X > CanW)
         {
             X = 0;
             Y += Dim.actualBoundingBoxAscent + Pad;
         }
         Ctx.fillText(Text[CharacterIndex], X, Y);
         X += Dim.width + Pad;
     }
}

