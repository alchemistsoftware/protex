function Assert(Expr: boolean): void
{
    if (Expr == false)
    {
        throw "Assert fail";
    }
}
function AddCatHandler(E: Event): void
{
    const EventElement = E.target as HTMLElement;
    const ProbablyAnExtrDefItem = EventElement.parentElement;
    if (ProbablyAnExtrDefItem == null)
    {
        throw "AddCatHandler's event's parent element was null";
    }
    if (ProbablyAnExtrDefItem.className != "extr-def-item")
    {
        throw "Tried to add a category to something that wasn't an 'extr-def-item'";
    }

    const CategoryFieldsContainer = document.createElement("div");
    CategoryFieldsContainer.className = "cat-fields-container";
    ProbablyAnExtrDefItem.appendChild(CategoryFieldsContainer);

    const CategoryFieldsItem = document.createElement("div");
    CategoryFieldsItem.className = "cat-fields-item";
    CategoryFieldsContainer.appendChild(CategoryFieldsItem);

    const CategoryNameInput = document.createElement("input");
    CategoryNameInput.className = "cat-name";
    CategoryFieldsItem.appendChild(CategoryNameInput);

    // Main python module selector
    const MainPyModuleSelect = document.createElement("select") as HTMLSelectElement;
    MainPyModuleSelect.className = "main-py-module-select";
    CategoryFieldsItem.appendChild(MainPyModuleSelect);

    const PluginsDirInput = document.getElementById("plugins-dir-input") as HTMLInputElement;
    if (PluginsDirInput == null)
    {
        throw "Couldn't get element 'plugins-dir-input'";
    }

    const Files = PluginsDirInput.files;
    if (Files != null)
    {
        // Add avaliable python files
        for (let FileIndex = 0;
             FileIndex < Files.length;
             ++FileIndex)
        {
            const File = Files.item(FileIndex);
            if (File == null)
            {
                continue;
            }
            const PyModuleNameOption = document.createElement("option");
            PyModuleNameOption.value = File.name;
            PyModuleNameOption.text = File.name;
            MainPyModuleSelect.add(PyModuleNameOption);
        }
    }

    // Pattern inputs
    const PatternsContainer = document.createElement("div");
    PatternsContainer.className = "patterns-container";
    CategoryFieldsItem.appendChild(PatternsContainer);

    const AddPatternButton = document.createElement("button");
    AddPatternButton.innerText = "New pattern";
    AddPatternButton.onclick = AddPatternHandler;
    PatternsContainer.appendChild(AddPatternButton);
}

function AddPatternHandler(E: Event): void
{
    const EventElement = E.target as HTMLElement;
    const ProbablyAPatternsContainer = EventElement.parentElement;
    if (ProbablyAPatternsContainer == null)
    {
        throw "AddCatHandler's event's parent element was null";
    }
    if (ProbablyAPatternsContainer.className != "patterns-container")
    {
        throw "Tried to add a pattern to something that wasn't a 'patterns-container'";
    }

    const PatternInput = document.createElement("input");
    PatternInput.className = "pattern-input";
    ProbablyAPatternsContainer.appendChild(PatternInput);
}

function AddExtrHandler(): void
{
    const ExtrDefsContainer = document.getElementById("extr-defs-container");
    if (ExtrDefsContainer == null)
    {
        throw "Couldn't get div with id 'extr-defs-container'";
    }

    const ExtrNameInput = document.getElementById("extr-name-input") as HTMLInputElement;
    if (ExtrNameInput == null)
    {
        throw "Couldn't get input with id 'extr-name-input'";
    }

    const ExtrCountryInput = document.getElementById("extr-country-input") as HTMLInputElement;
    if (ExtrCountryInput == null)
    {
        throw "Couldn't get input with id 'extr-country-input'";
    }

    const ExtrLanguageInput = document.getElementById("extr-language-input") as HTMLInputElement;
    if (ExtrLanguageInput == null)
    {
        throw "Couldn't get input with id 'extr-language-input'";
    }

    // Create new extractor definition item
    const ExtrDefItem = document.createElement("div");
    ExtrDefItem.className = "extr-def-item";
    ExtrDefsContainer.appendChild(ExtrDefItem);

    // Add name, country, and language to it.
    const NewExtrNameInput = document.createElement("input") as HTMLInputElement;
    NewExtrNameInput.className = "extr-name-input";
    NewExtrNameInput.value = ExtrNameInput.value;
    ExtrDefItem.appendChild(NewExtrNameInput);

    const NewExtrCountryInput = document.createElement("input") as HTMLInputElement;
    NewExtrCountryInput.className = "extr-country-input";
    NewExtrCountryInput.maxLength = 2;
    NewExtrCountryInput.value = ExtrCountryInput.value;
    ExtrDefItem.appendChild(NewExtrCountryInput);

    const NewExtrLanguageInput = document.createElement("input") as HTMLInputElement;
    NewExtrLanguageInput.className = "extr-language-input";
    NewExtrLanguageInput.value = ExtrLanguageInput.value;
    NewExtrLanguageInput.maxLength = 2;
    ExtrDefItem.appendChild(NewExtrLanguageInput);

    // Reset name
    ExtrNameInput.value = "";
    ExtrCountryInput.value = ""
    ExtrLanguageInput.value = ""

    // Attach an add category button.
    const AddCategoryButton = document.createElement("button");
    AddCategoryButton.innerText = "New category";
    AddCategoryButton.onclick = AddCatHandler;
    ExtrDefItem.appendChild(AddCategoryButton);
}

function UpdatePyModuleSelectOptions()
{
    const PluginsDirInput = document.getElementById("plugins-dir-input") as HTMLInputElement;
    if (PluginsDirInput == null)
    {
        throw "Couldn't get element 'plugins-dir-input'";
    }

    const Files = PluginsDirInput.files;
    if (Files != null)
    {
        const MainPyModuleSelectors =
            document.getElementsByClassName("main-py-module-select") as HTMLCollection;
        for (let SelectorIndex = 0;
             SelectorIndex < MainPyModuleSelectors.length;
             ++SelectorIndex)
        {
            const Elem = MainPyModuleSelectors.item(SelectorIndex);
            Assert(Elem != null);
            const Selector = Elem as HTMLSelectElement;

            // Clear options...
            Selector.innerHTML = "";

            // Add avaliable python files
            for (let FileIndex = 0;
                 FileIndex < Files.length;
                 ++FileIndex)
            {
                const File = Files.item(FileIndex);
                if (File == null)
                {
                    continue;
                }
                File.text().then(t => {console.log(t);});
                const PyModuleNameOption = document.createElement("option");
                PyModuleNameOption.value = File.name;
                PyModuleNameOption.text = File.name;
                Selector.add(PyModuleNameOption);
            }
        }
    }
}

interface cat_def
{
    Name: string,
    MainPyModule: string,
    Patterns: Array<string>,
};

interface extr_def
{
    Name: string,
    Country: string,
    Language: string,
    Categories: Array<cat_def>,
};

interface gracie_config
{
    PyIncludePath: string,
    ExtractorDefinitions: Array<extr_def>,
};

function GetElementById(ElemId: string): HTMLElement
{
    const Elem = document.getElementById(ElemId);
    if (Elem == null)
    {
        throw `Couldn't get element with id: '${ElemId}'`;
    }
    return Elem;
}

function GenJSONConfig(): string
{
    let RelPluginsDir: string = ".";
    const PluginsDirInput = GetElementById("plugins-dir-input") as HTMLInputElement;
    const Files = PluginsDirInput.files;
    if (Files != null)
    {
        const FirstFile = Files.item(0);
        if (FirstFile != null)
        {
            const SplitRelPath = FirstFile.webkitRelativePath.split('/');
            for (let PathPartIndex=0;
                 PathPartIndex < SplitRelPath.length - 1;
                 ++PathPartIndex)
            {
                RelPluginsDir += '/' + SplitRelPath[PathPartIndex];
            }
        }
    }
    else
    {
        Assert(false);
    }

    let ExtrDefs: extr_def[] = [];
    const ExtrDefsContainer = GetElementById("extr-defs-container");
    for (const ExtrDefItem of ExtrDefsContainer.children)
    {
        const NameInput = ExtrDefItem.getElementsByClassName("extr-name-input")
            .item(0) as HTMLInputElement | null;
        Assert(NameInput != null);

        const CountryInput = ExtrDefItem.getElementsByClassName("extr-country-input")
            .item(0) as HTMLInputElement | null;
        Assert(CountryInput != null);

        const LanguageInput = ExtrDefItem.getElementsByClassName("extr-language-input")
            .item(0) as HTMLInputElement | null;
        Assert(LanguageInput != null);

        let CatDefs: cat_def[] = [];
        const CategoryFieldsContainer = ExtrDefItem.getElementsByClassName("cat-fields-container")
            .item(0) as HTMLInputElement | null;
        Assert(CategoryFieldsContainer != null);

        for (const CatItem of (CategoryFieldsContainer as HTMLInputElement).children)
        {
            const CatNameInput = CatItem.getElementsByClassName("cat-name-input")
                .item(0) as HTMLInputElement | null;
            Assert(CatNameInput != null);

            const MainPyModuleSelect = CatItem.getElementsByClassName("main-py-module-select")
                .item(0) as HTMLInputElement | null;
            Assert(MainPyModuleSelect != null);

            CatDefs.push({
                Name: (CatNameInput as HTMLInputElement).value,
                MainPyModule: (MainPyModuleSelect as HTMLInputElement).value,
                Patterns: ["Bannanas!"],
            });
        }

        const NewExtrDef: extr_def = {
            Name: (NameInput as HTMLInputElement).value,
            Country: (CountryInput as HTMLInputElement).value,
            Language: (LanguageInput as HTMLInputElement).value,
            Categories: [],
        };

        ExtrDefs.push(NewExtrDef); // left off here... FIXME(cjb): this is broken?
    }

    let ConfigObj: gracie_config = {PyIncludePath: RelPluginsDir, ExtractorDefinitions: ExtrDefs};
    console.log(JSON.stringify(ConfigObj));
    return JSON.stringify(ConfigObj);
}

function Init(): void
{
    const AContainer = document.getElementById("acontainer")
    if (AContainer == null)
    {
        throw "Couldn't get acontainer element";
    }

    const SampleText = "Prep Cooks/Cooks Starting at $25 an Hour Qualifications\n    Restaurant: 1 year (Required)\n    Work authorization (Required)\n    High school or equivalent (Preferred)\nBenefits\n\Pulled from the full job description\n\Employee discount\n\Paid time off\n\Full Job Description\nCooks\nGreat Opportunity to work at a new all-seasons resort in Northern Catskills - Wylder Windham Hotel.\nWe are looking for a dedicated, passionate, and skilled person to become a part of our pre-opening kitchen team for our Babbler's Restaurant. Our four-season resort will offer 110 hotel rooms, 1 restaurant, 1 Bakery with 20 acres of land alongside the Batavia Kill River, our family-friendly, all-season resort is filled with endless opportunities. This newly reimagined property offers banquet, wedding, and event facilities. We are looking for someone who is both willing to roll up their sleeves and work hard and has a desire to produce a first-class experience for our guests. Looking for applicants who are positive, upbeat, team-oriented, and a people person.\nWylder is an ever growing hotel brand with locations in Lake Tahoe, California and Tilghman Maryland.\nLots of room for upward growth within the company at the Wylder Windham property and Beyond.\nYoung at heart, active, ambitious individuals encouraged to apply!\nMust work weekends, nights, holidays and be flexible with schedule. Must be able to lift 50 pounds and work a physical Labor Job.\nWylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family-friendly in all aspects!.\nWylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family friendly in all aspects!\nCompetitive Pay- starting at $25-$26+ per hour based on experience\nJob Type: Full-time/Part-Time\nJob Type: Full-time\nPay: From $25-$26+ per hour based on experience\nBenefits:\n    Employee discount\n\    Paid time off\nSchedule:\n    10 hour shift\n\    8 hour shift\n\    Every weekend\n\    Holidays\n\    Monday to Friday\n\    Weekend availability\nEducation:\n    High school or equivalent (Preferred)\nExperience:\n    cooking: 1 year (Preferred)\nWork Location: One location\nJob Type: Full-time\nPay: $25.00 - $26.00 per hour\nBenefits:\n    Employee discount\n\    Paid time off\nPhysical setting:\n    Casual dining restaurant\nSchedule:\n    8 hour shift\n\    Day shift\n\    Holidays\n\    Monday to Friday\n\    Night shift\n\    Weekend availability\nEducation:\n    High school or equivalent (Preferred)\nExperience:\n    Restaurant: 1 year (Required)";
    const TA = document.createElement("textarea");
    TA.innerText = SampleText;
    AContainer.appendChild(TA);

    const PluginsDirInput = document.createElement("input") as HTMLInputElement;
    PluginsDirInput.id = "plugins-dir-input";
    PluginsDirInput.type = "file";
    PluginsDirInput.setAttribute("webkitdirectory", "true");
    PluginsDirInput.setAttribute("multiple", "true");
    PluginsDirInput.onchange = UpdatePyModuleSelectOptions;
    AContainer.appendChild(PluginsDirInput);

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
    AddExtrButton.onclick = AddExtrHandler;
    NewExtrDefFieldsContainer.appendChild(AddExtrButton);

    const ExtrDefsContainer = document.createElement("div");
    ExtrDefsContainer.id = "extr-defs-container";
    AContainer.appendChild(ExtrDefsContainer);

    const GenConfButton = document.createElement("button");
    GenConfButton.innerText = "Generate config!";
    GenConfButton.onclick = GenJSONConfig;
    AContainer.appendChild(GenConfButton);
}

Init();
