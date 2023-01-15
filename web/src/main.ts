function AddEmptyCat(S: gracie_state, ExtrDefItem: HTMLElement): void
{
    AddCat(S, ExtrDefItem, "", "", []);
}

async function AddCat(S: gracie_state, ExtrDefItem: HTMLElement, Name: string, MainPyModule: string,
    Patterns: string[]): Promise<void>
{
    return new Promise(async (Res) =>
    {
        const CategoryFieldsContainer = document.createElement("div");
        CategoryFieldsContainer.className = "cat-fields-container";
        ExtrDefItem.appendChild(CategoryFieldsContainer);

        const CategoryFieldsItem = document.createElement("div");
        CategoryFieldsItem.className = "cat-fields-item";
        CategoryFieldsContainer.appendChild(CategoryFieldsItem);

        const CategoryNameInput = document.createElement("input");
        CategoryNameInput.className = "cat-name-input";
        CategoryNameInput.value = Name;
        CategoryFieldsItem.appendChild(CategoryNameInput);

        // Main python module selector
        const MainPyModuleSelect = document.createElement("select") as HTMLSelectElement;
        MainPyModuleSelect.className = "main-py-module-select";
        CategoryFieldsItem.appendChild(MainPyModuleSelect);

        // NOTE(cjb): First selector added to document is source of truth for avaliable modules..
        //  sot (source of truth)
        let SOTSelector = document.getElementById(
            "sot-main-py-module-select") as HTMLSelectElement | null;
        if (SOTSelector == null)
        {
            // Set sot id and ask server for options.
            MainPyModuleSelect.id = "sot-main-py-module-select";
            await PopulatePyModuleSelectOptions(MainPyModuleSelect, MainPyModule);
        }
        else // Copy SOT selector options
        {
            for (let SelectIndex = 0;
                 SelectIndex < SOTSelector.children.length;
                 ++SelectIndex)
            {
                const PyModuleNameOption = document.createElement("option");
                MainPyModuleSelect.add(PyModuleNameOption);

                PyModuleNameOption.text =
                    (SOTSelector.children[SelectIndex] as HTMLOptionElement).text;
                PyModuleNameOption.value =
                    (SOTSelector.children[SelectIndex] as HTMLOptionElement).value;

                // NOTE(cjb): Element needs to exist in DOM before you are allowed to screw with
                // selectedindex.
                if (PyModuleNameOption.text === MainPyModule)
                    MainPyModuleSelect.selectedIndex = SelectIndex;
            }
        }

        // Pattern inputs
        const PatternsContainer = document.createElement("div");
        PatternsContainer.className = "patterns-container";
        CategoryFieldsItem.appendChild(PatternsContainer);

        const AddPatternButton = document.createElement("button");
        AddPatternButton.innerText = "New pattern";
        AddPatternButton.onclick = () => AddPattern(S, PatternsContainer, "");
        PatternsContainer.appendChild(AddPatternButton);

        for (const P of Patterns) AddPattern(S, PatternsContainer, P);
        Res();
    });
}

interface gracie_state
{
    SPI: HTMLInputElement | null, // Selected pattern input
};

// On pattern selection set it as the "last selected pattern"
function MakeSelectedPattern(S: gracie_state, PatternInput: HTMLInputElement): void
{
    if (S.SPI != null)
        S.SPI.style.setProperty("border", "1px solid white");
    PatternInput.style.setProperty("border", "1px solid yellow");
    S.SPI = PatternInput;
}

function AddPattern(S: gracie_state, PatternsContainer: HTMLElement, Pattern: string): void
{
    const PatternInput = document.createElement("input");
    PatternInput.className = "pattern-input";
    PatternInput.value = Pattern;
    PatternInput.addEventListener("focus", () => MakeSelectedPattern(S, PatternInput));
    PatternsContainer.appendChild(PatternInput);

    const RemovePatternButton = document.createElement("button");
    RemovePatternButton.innerText = "Remove";
    RemovePatternButton.onclick = () =>
    {
        if (PatternInput === S.SPI)
        {
            S.SPI = null;
        }
        PatternInput.remove();
        RemovePatternButton.remove();
    }
    PatternsContainer.appendChild(RemovePatternButton);
}

function AddExtr(S: gracie_state, ExtrName: string, Country: string, Language: string): HTMLElement
{
    const ExtrDefsContainer = document.getElementById("extr-defs-container");
    if (ExtrDefsContainer == null)
    {
        throw "Couldn't get div with id 'extr-defs-container'";
    }

    // Create new extractor definition item
    const ExtrDefItem = document.createElement("div");
    ExtrDefItem.className = "extr-def-item";
    ExtrDefsContainer.appendChild(ExtrDefItem);

    // Add name, country, and language to it.
    const NewExtrNameInput = document.createElement("input") as HTMLInputElement;
    NewExtrNameInput.className = "extr-name-input";
    NewExtrNameInput.value = ExtrName;
    ExtrDefItem.appendChild(NewExtrNameInput);

    const NewExtrCountryInput = document.createElement("input") as HTMLInputElement;
    NewExtrCountryInput.className = "extr-country-input";
    NewExtrCountryInput.maxLength = 2;
    NewExtrCountryInput.value = Country;
    ExtrDefItem.appendChild(NewExtrCountryInput);

    const NewExtrLanguageInput = document.createElement("input") as HTMLInputElement;
    NewExtrLanguageInput.className = "extr-language-input";
    NewExtrLanguageInput.value = Language;
    NewExtrLanguageInput.maxLength = 2;
    ExtrDefItem.appendChild(NewExtrLanguageInput);

    // Attach an add category button.
    const AddCategoryButton = document.createElement("button");
    AddCategoryButton.innerText = "New category";
    AddCategoryButton.onclick = () => AddEmptyCat(S, ExtrDefItem);
    ExtrDefItem.appendChild(AddCategoryButton);

    return ExtrDefItem;
}

async function PopulatePyModuleSelectOptions(Selector: HTMLSelectElement,
    SelectText: string): Promise<void>
{
    return new Promise(async (Res) =>
    {
        Selector.innerText = "";

        const PyEntries = (await GETIncludePathAndEntries()).Entries;
        let SelectIndex = -1;
        PyEntries.forEach((PyModule, PyModuleIndex) =>
        {
            const PyModuleNameOption = document.createElement("option");
            PyModuleNameOption.value = PyModule;
            PyModuleNameOption.text = PyModule;
            if (PyModule === SelectText)
            {
                SelectIndex = PyModuleIndex;
            }
            Selector.add(PyModuleNameOption);
        });
        Selector.selectedIndex = SelectIndex;
        Res();
    });
}

interface cat_def
{
    Name: string,
    MainPyModule: string,
    Patterns: string[],
};

interface extr_def
{
    Name: string,
    Country: string,
    Language: string,
    Categories: cat_def[],
};

interface gracie_config
{
    PyIncludePath: string,
    ExtractorDefinitions: extr_def[],
};

function GetElementByIDOrThrow(ElemId: string): HTMLElement
{
    const Elem = document.getElementById(ElemId);
    if (Elem == null)
    {
        throw `Couldn't get element with id: '${ElemId}'`;
    }
    return Elem;
}

async function ImportJSONConfig(S: gracie_state, E: Event): Promise<void>
{
    return new Promise(async (Res, Rej) =>
    {
        if ((E.target == null) ||
            ((E.target as HTMLElement).id != "import-config-input"))
        {
            throw "Bad event target";
        }

        // Clear out current definitions if any.
        const ExtrDefsContainer = GetElementByIDOrThrow("extr-defs-container");
        ExtrDefsContainer.innerHTML = "";

        // Get first file ( should  only be one anyway )
        const Files = ((E.target as HTMLInputElement).files as FileList);
        if (Files.length == 0)
        {
            return;
        }
        Files[0].text().then(async Text =>
        {
            const JSONConfig = JSON.parse(Text);
            for (const ExtrDef of JSONConfig.ExtractorDefinitions)
            {
                const ExtrDefElem = AddExtr(S, ExtrDef.Name, ExtrDef.Country, ExtrDef.Language);
                for (const Cat of ExtrDef.Categories)
                    await AddCat(S, ExtrDefElem, Cat.Name, Cat.MainPyModule, Cat.Patterns);
            }
        });
        Res();
    });
}

interface py_include_path_and_entries
{
    PyIncludePath: string,
    Entries: string[],
};

async function GETIncludePathAndEntries(): Promise<py_include_path_and_entries>
{
    return new Promise((Res, Rej) =>
    {
        const Req = new Request("/py-include-path");
        fetch(Req).then(Res => (Res.body as ReadableStream))
        .then(RS =>
        {
            const Reader = RS.getReader();
            Reader.read().then(Stream =>
            {
                const IncludePathAndEntriesJSONStr = new TextDecoder().decode(Stream.value);
                Res(JSON.parse(IncludePathAndEntriesJSONStr));
            });
        });
    });
}

async function GenJSONConfig(): Promise<string>
{
    return new Promise(async (Res, Rej) =>
    {
        const PyIncludePath = (await GETIncludePathAndEntries()).PyIncludePath;
        let ExtrDefs: extr_def[] = [];
        const ExtrDefsContainer = GetElementByIDOrThrow("extr-defs-container");
        for (const ExtrDefItem of ExtrDefsContainer.children)
        {
            const NameInput = ExtrDefItem.getElementsByClassName("extr-name-input")
                .item(0) as HTMLInputElement | null;

            const CountryInput = ExtrDefItem.getElementsByClassName("extr-country-input")
                .item(0) as HTMLInputElement | null;

            const LanguageInput = ExtrDefItem.getElementsByClassName("extr-language-input")
                .item(0) as HTMLInputElement | null;

            let CatDefs: cat_def[] = [];
            for (const CatFieldsContainer of ExtrDefItem.getElementsByClassName("cat-fields-container"))
            {
                for (const CatItem of CatFieldsContainer.children)
                {
                    const CatNameInput = CatItem.getElementsByClassName("cat-name-input")
                        .item(0) as HTMLInputElement | null;

                    const MainPyModuleSelect = CatItem.getElementsByClassName("main-py-module-select")
                        .item(0) as HTMLInputElement | null;

                    let Patterns: string[] = [];
                    const PatternsContainer = CatItem.getElementsByClassName("patterns-container")
                        .item(0) as HTMLElement | null;
                    for (const PatternItem of (PatternsContainer as HTMLElement)
                         .getElementsByClassName("pattern-input"))
                    {
                        Patterns.push((PatternItem as HTMLInputElement).value);
                    }

                    CatDefs.push({
                        Name: (CatNameInput as HTMLInputElement).value,
                        MainPyModule: (MainPyModuleSelect as HTMLInputElement).value,
                        Patterns: Patterns,
                    });
                }
            }

            const NewExtrDef: extr_def = {
                Name: (NameInput as HTMLInputElement).value,
                Country: (CountryInput as HTMLInputElement).value,
                Language: (LanguageInput as HTMLInputElement).value,
                Categories: CatDefs,
            };

            ExtrDefs.push(NewExtrDef);
        }

        let ConfigObj: gracie_config = {PyIncludePath: PyIncludePath, ExtractorDefinitions: ExtrDefs};
        Res(JSON.stringify(ConfigObj));
    });
}

function EscapeRegex(Regex: string): string
{
    // NOTE(cjb): $& = whole matched string
    return Regex.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function RegexCaptureAnyNum(Regex: string): string
{
    return Regex.replace(/[\d]/g, "\\d");
}

function Regexify(Str: string): string
{
    return RegexCaptureAnyNum(EscapeRegex(Str.toLowerCase()));
}

function RegexifyLiteral(Str: string): string
{
    return EscapeRegex(Str.toLowerCase());
}

///
/// Sets up the initial DOM structure, and state.
///
function Init(): void
{
    // Declare app state
    let S = {} as gracie_state;

    // Root container to add dom elements to.
    const AContainer = document.getElementById("acontainer")
    if (AContainer == null)
    {
        throw "Couldn't get acontainer element";
    }

    const ABox = document.createElement("div");
    ABox.style.width = "95vw";
    ABox.style.height = "40vh";
    ABox.style.maxWidth = "95vw";
    ABox.style.maxHeight = "40vh";
    ABox.style.margin = "10px";
    ABox.style.display = "inline-block";
    //ABox.style.border = "1px solid red";
    ABox.style.overflow = "hidden";
    AContainer.appendChild(ABox);

    // Document's text area
    const SampleText = "Prep Cooks/Cooks Starting at $25 an Hour Qualifications\n    Restaurant: 1 year (Required)\n    Work authorization (Required)\n    High school or equivalent (Preferred)\nBenefits\n\Pulled from the full job description\n\Employee discount\n\Paid time off\n\Full Job Description\nCooks\nGreat Opportunity to work at a new all-seasons resort in Northern Catskills - Wylder Windham Hotel.\nWe are looking for a dedicated, passionate, and skilled person to become a part of our pre-opening kitchen team for our Babbler's Restaurant. Our four-season resort will offer 110 hotel rooms, 1 restaurant, 1 Bakery with 20 acres of land alongside the Batavia Kill River, our family-friendly, all-season resort is filled with endless opportunities. This newly reimagined property offers banquet, wedding, and event facilities. We are looking for someone who is both willing to roll up their sleeves and work hard and has a desire to produce a first-class experience for our guests. Looking for applicants who are positive, upbeat, team-oriented, and a people person.\nWylder is an ever growing hotel brand with locations in Lake Tahoe, California and Tilghman Maryland.\nLots of room for upward growth within the company at the Wylder Windham property and Beyond.\nYoung at heart, active, ambitious individuals encouraged to apply!\nMust work weekends, nights, holidays and be flexible with schedule. Must be able to lift 50 pounds and work a physical Labor Job.\nWylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family-friendly in all aspects!.\nWylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family friendly in all aspects!\nCompetitive Pay- starting at $25-$26+ per hour based on experience\nJob Type: Full-time/Part-Time\nJob Type: Full-time\nPay: From $25-$26+ per hour based on experience\nBenefits:\n    Employee discount\n\    Paid time off\nSchedule:\n    10 hour shift\n\    8 hour shift\n\    Every weekend\n\    Holidays\n\    Monday to Friday\n\    Weekend availability\nEducation:\n    High school or equivalent (Preferred)\nExperience:\n    cooking: 1 year (Preferred)\nWork Location: One location\nJob Type: Full-time\nPay: $25.00 - $26.00 per hour\nBenefits:\n    Employee discount\n\    Paid time off\nPhysical setting:\n    Casual dining restaurant\nSchedule:\n    8 hour shift\n\    Day shift\n\    Holidays\n\    Monday to Friday\n\    Night shift\n\    Weekend availability\nEducation:\n    High school or equivalent (Preferred)\nExperience:\n    Restaurant: 1 year (Required)";
    const TA = document.createElement("textarea");
    TA.innerText = SampleText;
    TA.style.border = "none";
    TA.style.resize = "none";
    TA.style.width = "100%";
    TA.style.height = "100%";
    TA.style.display = "none";
    TA.addEventListener("blur", () =>
    {
        TA.style.display = "none";
        const InnerText = TA.innerText;
        SpanText.innerHTML = InnerText.slice(0, TA.selectionStart) + `<span class="noice">` +
            InnerText.slice(TA.selectionStart, TA.selectionEnd) + "</span>" +
            InnerText.slice(TA.selectionEnd);
        SpanText.style.display = "inline-block";

        if (S.SPI != null)
        {
            S.SPI.value = Regexify(InnerText.slice(TA.selectionStart, TA.selectionEnd));
        }
    });
    ABox.appendChild(TA);

    const SpanText = document.createElement("span");
    SpanText.innerText = TA.innerText;
    SpanText.onclick = () =>
    {
        // Toggle TA selection
        SpanText.style.display = "none";
        TA.style.display = "inline-block";
        TA.focus();
    }
    ABox.appendChild(SpanText);

    // Import existing configuration input
    const ImportConfigLabel = document.createElement("label");
    ImportConfigLabel.setAttribute("for", "import-config-input");
    ImportConfigLabel.innerText = "Import config:";
    AContainer.appendChild(ImportConfigLabel);

    const ImportConfigInput = document.createElement("input");
    ImportConfigInput.id = "import-config-input";
    ImportConfigInput.type = "file";
    ImportConfigInput.onchange = async (E) =>
    {
        await ImportJSONConfig(S, E);
    }
    AContainer.appendChild(ImportConfigInput);

    const NewExtrDefFieldsContainer = document.createElement("div");
    NewExtrDefFieldsContainer.id = "new-extr-def-fields-container";
    AContainer.appendChild(NewExtrDefFieldsContainer);

    const ExtrNameInput = document.createElement("input");
    ExtrNameInput.id = "extr-name-input";
    NewExtrDefFieldsContainer.appendChild(ExtrNameInput);

    const ExtrCountryInput = document.createElement("input");
    ExtrCountryInput.id = "extr-country-input";
    ExtrCountryInput.maxLength = 2;
    NewExtrDefFieldsContainer.appendChild(ExtrCountryInput);

    const ExtrLanguageInput = document.createElement("input");
    ExtrLanguageInput.id = "extr-language-input";
    ExtrLanguageInput.maxLength = 2;
    NewExtrDefFieldsContainer.appendChild(ExtrLanguageInput);

    const AddExtrButton = document.createElement("button");
    AddExtrButton.innerText = "New extractor";
    AddExtrButton.onclick = () =>
	{
		AddExtr(S, ExtrNameInput.value, ExtrCountryInput.value, ExtrLanguageInput.value);

        // Reset inputs
        ExtrNameInput.value = "";
        ExtrCountryInput.value = "";
        ExtrLanguageInput.value = "";
	};
    NewExtrDefFieldsContainer.appendChild(AddExtrButton);

    const ExtrDefsContainer = document.createElement("div");
    ExtrDefsContainer.id = "extr-defs-container";
    AContainer.appendChild(ExtrDefsContainer);

    const DEBUGDisplayConfig = document.createElement("span");
    DEBUGDisplayConfig.className = "debug-display-config";

    const GenConfButton = document.createElement("button");
    GenConfButton.innerText = "Generate config!";
    GenConfButton.onclick = async () => {
        const JSONConfigStr = await GenJSONConfig();
        DEBUGDisplayConfig.innerText = JSONConfigStr;
    }
    AContainer.appendChild(GenConfButton);
    AContainer.appendChild(DEBUGDisplayConfig);
}

Init();