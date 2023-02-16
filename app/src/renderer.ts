interface py_include_path_and_entries
{
    PyIncludePath: string,
    Entries: string[],
}

function AddEmptyCat(S: protex_state, ExtrDefItem: HTMLElement, ExtractorIndex: number): void
{
    AddCat(S, ExtrDefItem, "", "", "", "", [], ExtractorIndex);
}

//TODO(cjb): Get category/conditions in toolbar as well.
function AddCat(S: protex_state, ExtrDefItem: HTMLElement, Name: string, ResolvesWith: string,
    Conditions: string, MainPyModule: string, Patterns: string[], ExtractorIndex: number): void
{
    let Cat = {
        Name: Name,
        Conditions: Conditions,
    };
    S.Extractors[ExtractorIndex].Categories.push(Cat);
    S.Extractors[ExtractorIndex].Patterns = Patterns.slice(0);

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

    const ConditionsInput = document.createElement("input");
    ConditionsInput.className = "conditions-input";
    ConditionsInput.value = Conditions;
    ConditionsInput.addEventListener("keydown", (E: Event) =>
    {
        const InputE = (E as KeyboardEvent);
        if (InputE.key === '~')
        {
            E.preventDefault();

            const AutoCompleteMenu = TryGetElementByID("auto-complete-menu");
            AutoCompleteMenu.innerHTML = "";
            const PatternsContainer = TryGetElementByID("patterns-container");
            let EntryIndex = 0;
            for (const Elem of PatternsContainer
                 .getElementsByClassName("pattern-input"))
            {
                const AutoCompleteEntry = document.createElement("li");
                AutoCompleteEntry.setAttribute("tabIndex", "0");
                AutoCompleteEntry.style.display = "inline-block";
                AutoCompleteEntry.style.padding = "1px 5px"
                AutoCompleteEntry.innerText = (Elem as HTMLInputElement).value;
                AutoCompleteEntry.value = EntryIndex;
                EntryIndex += 1;
                AutoCompleteEntry.addEventListener("keyup", (E: Event) =>
                {
                    E.preventDefault();
                    if ((E as KeyboardEvent).key === "Enter")
                    {
                        const OptSelectionStart = ConditionsInput.selectionStart;
                        if (OptSelectionStart !== null)
                        {
                            const SelectionStart = OptSelectionStart as number;
                            ConditionsInput.value = ConditionsInput.value.slice(0, SelectionStart) +
                                `#${AutoCompleteEntry.value}` +
                                ConditionsInput.value.slice(SelectionStart);
                        }
                        AutoCompleteMenu.innerHTML = "";
                        ConditionsInput.focus();
                    }
                });
                AutoCompleteMenu.appendChild(AutoCompleteEntry);
            }
            if (EntryIndex > 0)
            {
                (AutoCompleteMenu.children[0] as HTMLElement).focus();
            }
        }
    });
    CategoryFieldsItem.appendChild(ConditionsInput);

    const RemoveCategoryButton = document.createElement("button");
    RemoveCategoryButton.innerText = "Remove Category";
    RemoveCategoryButton.onclick = () =>
    {
        CategoryFieldsItem.remove();
    };
    CategoryFieldsItem.appendChild(RemoveCategoryButton);

}


function LastSelectedPatternInput(): HTMLInputElement | null
{
    const PatternInputs = document.getElementsByClassName("pattern-input");
    for (const Elem of PatternInputs)
    {
        if ((Elem.getAttribute("IsSelected") as string) == "true")
            return (Elem as HTMLInputElement);
    }
    return null;
}

function UpdateSelectedPattern(TargetPatternInput: HTMLInputElement): void
{
    const PrevSelectedPatternInput = LastSelectedPatternInput();
    if (PrevSelectedPatternInput != null)
    {
        PrevSelectedPatternInput.setAttribute("IsSelected", "false");
    }
    TargetPatternInput.setAttribute("IsSelected", "true");

    const TextAreaText = (TryGetElementByID("text-area") as HTMLTextAreaElement).value;
    const PreText = TryGetElementByID("pre-text");
    let SpanifiedText = "";
    let Offset = 0;
    const Re = RegExp(TargetPatternInput.value, "gi"); //TODO(cjb): What flags do I pass here?
    let Matches: RegExpExecArray | null;
    while ((Matches = Re.exec(TextAreaText)) !== null)
    {
        const Match = Matches[0];
        const SO = Re.lastIndex - Match.length;
        const EO = Re.lastIndex;
        const LHS = TextAreaText.substring(Offset, SO);
        const RHS = '<span class="noice">' + TextAreaText.substring(SO, EO) + '</span>';

        SpanifiedText += LHS + RHS;
        Offset = EO;
        break;
    }
	SpanifiedText += TextAreaText.substring(Offset);
    PreText.innerHTML = SpanifiedText;
}

function AddPattern(S: protex_state, PatternsContainer: HTMLElement, Pattern: string): void
{
    const PatternEntry = document.createElement("dib");
    PatternEntry.className = "pattern-entry";
    PatternsContainer.appendChild(PatternEntry);

    const PatternInput = document.createElement("input");
    PatternInput.className = "pattern-input";
    PatternInput.setAttribute("IsSelected", "false");
    PatternInput.value = Pattern;
    PatternInput.addEventListener("focus", () => UpdateSelectedPattern(PatternInput));
    PatternInput.addEventListener("input", () => UpdateSelectedPattern(PatternInput));
    PatternEntry.appendChild(PatternInput);

    const RemovePatternButton = document.createElement("button");
    RemovePatternButton.className = "pattern-entry-button";
    RemovePatternButton.innerText = "-";
    RemovePatternButton.onclick = () =>
    {
        PatternInput.remove();
        RemovePatternButton.remove();
    }
    PatternEntry.appendChild(RemovePatternButton);
}

function AddExtr(S: protex_state, ExtrName: string): HTMLElement
{
    const ExtrDefsContainer = document.getElementById("extr-defs-container");
    if (ExtrDefsContainer == null)
    {
        throw "Couldn't get div with id 'extr-defs-container'";
    }

    const NewExtractorOption = document.createElement("option");
    NewExtractorOption.text = ExtrName;
    NewExtractorOption.value = ExtrName;
    const ExtractorSelect = TryGetElementByID("extractor-select") as HTMLSelectElement;
    ExtractorSelect.add(NewExtractorOption);

    // Now select new option

    let OptionIndex = 0;
    for (let Option of ExtractorSelect.options)
    {
        if (Option.value === ExtrName)
        {
            ExtractorSelect.selectedIndex = OptionIndex;
        }
        OptionIndex += 1;
    }

    const ExtrDefItem = document.createElement("div");
    ExtrDefItem.className = "extr-def-item";
    ExtrDefsContainer.appendChild(ExtrDefItem);

    const NewExtrDef: extr_def = {
        Name: ExtrName,
        Categories: [],
        Patterns: [],
    };
    S.Extractors.push(NewExtrDef);

    const AddCategoryButton = document.createElement("button");
    AddCategoryButton.innerText = "New category";
    AddCategoryButton.onclick = () => AddEmptyCat(S, ExtrDefItem, S.Extractors.length - 1);
    ExtrDefItem.appendChild(AddCategoryButton);

//    const RemoveExtractorButton = document.createElement("button");
//    RemoveExtractorButton.innerText = "Remove Extractor";
//    RemoveExtractorButton.onclick = () =>
//    {
//        ExtrDefItem.remove();
//    };
//    ExtrDefItem.appendChild(RemoveExtractorButton);

    return ExtrDefItem;
}

function PopulatePyModuleSelectOptions(S: protex_state, Selector: HTMLSelectElement,
    SelectText: string): void
{
    Selector.innerText = "";

    const AddScriptButton = document.createElement("option");
    AddScriptButton.text = "New Script";
    AddScriptButton.value = "New Script";
    Selector.add(AddScriptButton);

    const PyEntries = S.ScriptNames;
    let SelectIndex = -1;
    PyEntries.forEach((PyModule, PyModuleIndex) =>
    {
        const PyModuleNameOption = document.createElement("option");
        PyModuleNameOption.value = PyModule;
        PyModuleNameOption.text = PyModule;
        if (PyModule === SelectText)
        {
            SelectIndex = PyModuleIndex + 1;
        }
        Selector.add(PyModuleNameOption);
    });

    Selector.selectedIndex = SelectIndex;
}

interface cat_def
{
    Name: string,
    Conditions: string,
};

interface extr_def
{
    Name: string,
    Categories: cat_def[],
    Patterns: string[],
};

interface protex_window extends Window
{
    ProtexAPI: any
};

interface protex_state
{
    ScriptNames: string[],
    Extractors: extr_def[],
};

const ProtexWindow = window as unknown as protex_window;

function TryGetElementByClassName(ParentElem: Element, ClassName: string,
    Index: number): HTMLElement
{
    const Elem = ParentElem.getElementsByClassName(ClassName)
        .item(Index) as HTMLElement | null;
    if (Elem == null)
    {
        throw `Couldn't get element with class: '${ClassName}' at index: '${Index}'`;
    }
    return Elem;
}

function TryGetElementByID(ElemId: string): HTMLElement
{
    const Elem = document.getElementById(ElemId);
    if (Elem == null)
    {
        throw `Couldn't get element with id: '${ElemId}'`;
    }
    return Elem;
}

function ImportJSONConfig(S: protex_state, E: Event): void
{
    if ((E.target == null) ||
        ((E.target as HTMLElement).id != "import-config-input"))
    {
        throw "Bad event target";
    }

    // Clear out current definitions if any.
    const ExtrDefsContainer = TryGetElementByID("extr-defs-container");
    ExtrDefsContainer.innerHTML = "";

    // Get first file ( should  only be one anyway )
    const Files = ((E.target as HTMLInputElement).files as FileList);
    if (Files.length == 0)
    {
        return;
    }
    Files[0].text().then(Text =>
    {
        const PatternsContainer = TryGetElementByID("patterns-container");
        const JSONConfig = JSON.parse(Text);
        let ExtrDefIndex = 0;
        for (const ExtrDef of JSONConfig.ExtractorDefinitions)
        {
            const ExtrDefElem = AddExtr(S, ExtrDef.Name);
            for (const Cat of ExtrDef.Categories)
                AddCat(S, ExtrDefElem, Cat.Name, Cat.ResolvesWith, Cat.Conditions, Cat.MainPyModule,
                       Cat.Patterns, ExtrDefIndex);

            for (const P of ExtrDef.Patterns)
            {
                AddPattern(S, PatternsContainer, P);
            }
            ExtrDefIndex += 1;
        }
    });
}

function GenJSONConfig(S: protex_state): string
{
    let ExtrDefs: extr_def[] = [];
    const ExtrDefsContainer = TryGetElementByID("extr-defs-container");
    for (const ExtrDefItem of ExtrDefsContainer.children)
    {
        const NameInput = TryGetElementByClassName(
            ExtrDefItem, "extr-name-input", 0) as HTMLInputElement;

        const PatternsContainer = TryGetElementByID("patterns-container");
        let Patterns: string[] = [];
        for (const Elem of PatternsContainer.getElementsByClassName("pattern-input"))
        {
            Patterns.push((Elem as HTMLInputElement).value);
        }

        let CatDefs: cat_def[] = [];
        for (const CatFieldsContainer of ExtrDefItem.getElementsByClassName("cat-fields-container"))
        {
            for (const CatItem of CatFieldsContainer.children)
            {
                const CatNameInput = TryGetElementByClassName(
                    CatItem, "cat-name-input", 0) as HTMLInputElement;
                const ConditionsInput = TryGetElementByClassName(
                    CatItem, "conditions-input", 0) as HTMLInputElement;

                CatDefs.push({
                    Name: CatNameInput.value,
                    Conditions: ConditionsInput.value,
                });
            }
        }

        const NewExtrDef: extr_def = {
            Name: (NameInput as HTMLInputElement).value,
            Categories: CatDefs,
            Patterns: Patterns
        };
        ExtrDefs.push(NewExtrDef);
    }

    console.log({ConfName: ConfName,
        ExtractorDefinitions: ExtrDefs});
    return JSON.stringify({ConfName: ConfName,
        ExtractorDefinitions: ExtrDefs});
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

function GetUserInput(): Promise<string>
{
    function FinishedInput(InputElem: HTMLInputElement): Promise<void>
    {
        return new Promise<void>((Resolve) => {
            InputElem.onkeyup = (E: KeyboardEvent) => {
                if (E.key === "Enter")
                {
                    Resolve();
                }
                else if (E.key === "Escape")
                {
                    InputElem.value = "";
                    Resolve();
                }
            }
        });
    }

    return new Promise<string>((Resolve) => {
        const UserInput = document.createElement("input");
        UserInput.style.position = "fixed";
        UserInput.style.left = "50%";
        UserInput.style.top = "50%";
        UserInput.style.transform = "translate(-50%, -50%)";
        document.body.appendChild(UserInput);
        UserInput.focus();
        FinishedInput(UserInput).then(() =>
        {
            const Result = UserInput.value;
            UserInput.remove();
            Resolve(Result);
        });
    });
}

const ConfName = "webs_conf.json"; //TODO(cjb): Make this a texbox

//
// Initialization
//

let S = {} as protex_state;
S.Extractors = [];
S.ScriptNames = [];

ProtexWindow.ProtexAPI.GetScriptNames()
    .then((Result: string[]) =>
{
    S.ScriptNames = Result.slice(0);

    // Root container to add dom elements to.
    const AContainer = document.getElementById("a-container")
    if (AContainer == null)
    {
        throw "Couldn't get acontainer element";
    }

    const ToolbarContainer = document.createElement("div");
    ToolbarContainer.id = "toolbar-container";
    AContainer.appendChild(ToolbarContainer);

    // Import existing configuration input
    const ImportConfigInput = document.createElement("input");
    ImportConfigInput.id = "import-config-input";
    ImportConfigInput.setAttribute("accept", ".json");
    ImportConfigInput.type = "file";
    ImportConfigInput.style.display = "none";
    ImportConfigInput.onchange = (E) => ImportJSONConfig(S, E);
    ToolbarContainer.appendChild(ImportConfigInput);

    const ImportConfigTab = document.createElement("div");
    ImportConfigTab.tabIndex = 0;
    ImportConfigTab.className = "toolbar-item";
    ImportConfigTab.onkeypress = (E: KeyboardEvent) =>
    {
        if (E.key === "Enter")
        {
            ImportConfigInput.click()
        }
    };
    ImportConfigTab.onclick = () => ImportConfigInput.click();
    ImportConfigTab.innerText = "Import";
    ToolbarContainer.appendChild(ImportConfigTab);

    const RunExtractorButton = document.createElement("button");
    RunExtractorButton.style.display = "none";
    RunExtractorButton.onclick = () =>
    {
        const ConfigStr = GenJSONConfig(S);
        ProtexWindow.ProtexAPI.WriteConfig(ConfigStr).then(() =>
        {
            ProtexWindow.ProtexAPI.RunExtractor(ConfName, TA.value)
                .then((ExtractorOut: any) =>
            {
                console.log(ExtractorOut);
            });
        });
    }
    ToolbarContainer.appendChild(RunExtractorButton);

    const RunExtractorTab = document.createElement("div");
    RunExtractorTab.onkeypress = (E: KeyboardEvent) =>
    {
        if (E.key === "Enter")
        {
            RunExtractorButton.click()
        }
    };
    RunExtractorTab.onclick = () => RunExtractorButton.click();
    RunExtractorTab.tabIndex = 0;
    RunExtractorTab.className = "toolbar-item";
    RunExtractorTab.innerText = "Run";
    ToolbarContainer.appendChild(RunExtractorTab);

    const ActiveScriptSelect = document.createElement("select");
    let PrevSelectedScriptIndex = -1;
    ActiveScriptSelect.onchange = () => {
        let NewScriptName = ActiveScriptSelect.value;
        if (NewScriptName === "New Script")
        {
            GetUserInput().then((Result) => {
                NewScriptName = Result;

                if (NewScriptName === "")
                {
                    // Make selected option nothing if it's just new script option.

                    ActiveScriptSelect.selectedIndex = PrevSelectedScriptIndex;
                    return;
                }
                PrevSelectedScriptIndex = ActiveScriptSelect.selectedIndex;

                ScriptEditingTA.value =
                    `def protex_main(text: str, so: int, eo: int) -> str:\n    return ""`;
                ScriptEditingTA.setAttribute("name", NewScriptName);
                ProtexWindow.ProtexAPI.WriteScript(NewScriptName, ScriptEditingTA.value)
                    .then(() =>
                {
                    ProtexWindow.ProtexAPI.GetScriptNames()
                        .then((Result: string[]) =>
                    {
                        S.ScriptNames = Result.slice(0);
                        PopulatePyModuleSelectOptions(S, ActiveScriptSelect, NewScriptName);
                    });
                });
            });
        }
        else // Didn't select 'New Script'
        {
            PrevSelectedScriptIndex = ActiveScriptSelect.selectedIndex;
            const OldScriptName = ScriptEditingTA.getAttribute("name");
            if (OldScriptName !== null)
            {
                ProtexWindow.ProtexAPI.WriteScript((OldScriptName as string), ScriptEditingTA.value);
            }

            ProtexWindow.ProtexAPI.ReadScript(NewScriptName).then((Result: string) =>
            {
                ScriptEditingTA.setAttribute("name", NewScriptName);
                ScriptEditingTA.value = Result;
            });
        }
    };
    PopulatePyModuleSelectOptions(S, ActiveScriptSelect, "");
    ToolbarContainer.appendChild(ActiveScriptSelect);

    const ExtractorSelect = document.createElement("select");
    ExtractorSelect.id = "extractor-select";
    let PrevSelectedExtractorIndex = -1;
    ExtractorSelect.onchange = () =>
    {
        if (ExtractorSelect.value === "New Extractor")
        {
            GetUserInput().then((Result) => {
                const NewExtractorName = Result;
                if (NewExtractorName === "")
                {
                    ExtractorSelect.selectedIndex = PrevSelectedExtractorIndex;
                    return;
                }
                PrevSelectedExtractorIndex = ActiveScriptSelect.selectedIndex;
                AddExtr(S, NewExtractorName);
            });
        }
        else // Otherwise switch extractors
        {
            PrevSelectedExtractorIndex = ActiveScriptSelect.selectedIndex;
        }
    }
    const AddExtractorOption = document.createElement("option");
    AddExtractorOption.text = "New Extractor";
    AddExtractorOption.value = "New Extractor";
    ExtractorSelect.add(AddExtractorOption);

    ExtractorSelect.selectedIndex = -1;
    ToolbarContainer.appendChild(ExtractorSelect);

    const ABBoxContainer = document.createElement("div");
    ABBoxContainer.id = "ab-box-container";
    AContainer.appendChild(ABBoxContainer);

    const ABox = document.createElement("div");
    ABox.className = "ab-item";
    ABBoxContainer.appendChild(ABox);

    const BBox = document.createElement("div");
    BBox.className = "ab-item";
    ABBoxContainer.appendChild(BBox);

    const PatternsContainer = document.createElement("div");
    PatternsContainer.id = "patterns-container";
    BBox.appendChild(PatternsContainer);

    const ScriptEditingTA = document.createElement("textarea");
    ScriptEditingTA.id = "script-editing-ta";
    ScriptEditingTA.onkeyup = (E: KeyboardEvent) =>
    {
        if (E.ctrlKey && E.key === "s")
        {
            const ScriptName = ScriptEditingTA.getAttribute("name");
            if (ScriptName !== null)
            {
                ProtexWindow.ProtexAPI.WriteScript((ScriptName as string), ScriptEditingTA.value);
            }
        }
    }
    ScriptEditingTA.setAttribute("spellcheck", "false");
    BBox.appendChild(ScriptEditingTA);

    const AddPatternButton = document.createElement("button");
    AddPatternButton.innerText = "+";
    AddPatternButton.className = "pattern-entry-button";
    AddPatternButton.onclick = () => AddPattern(S, PatternsContainer, "");
    PatternsContainer.appendChild(AddPatternButton);

    // Document's text area
    const DEBUGText = "Prep Cooks/Cooks Starting at $25 an Hour Qualifications\n    Restaurant: 1 year (Required)\n    Work authorization (Required)\n    High school or equivalent (Preferred)\nBenefits\n\Pulled from the full job description\n\Employee discount\n\Paid time off\n\Full Job Description\nCooks\nGreat Opportunity to work at a new all-seasons resort in Northern Catskills - Wylder Windham Hotel.\nWe are looking for a dedicated, passionate, and skilled person to become a part of our pre-opening kitchen team for our Babbler's Restaurant. Our four-season resort will offer 110 hotel rooms, 1 restaurant, 1 Bakery with 20 acres of land alongside the Batavia Kill River, our family-friendly, all-season resort is filled with endless opportunities. This newly reimagined property offers banquet, wedding, and event facilities. We are looking for someone who is both willing to roll up their sleeves and work hard and has a desire to produce a first-class experience for our guests. Looking for applicants who are positive, upbeat, team-oriented, and a people person.\nWylder is an ever growing hotel brand with locations in Lake Tahoe, California and Tilghman Maryland.\nLots of room for upward growth within the company at the Wylder Windham property and Beyond.\nYoung at heart, active, ambitious individuals encouraged to apply!\nMust work weekends, nights, holidays and be flexible with schedule. Must be able to lift 50 pounds and work a physical Labor Job.\nWylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family-friendly in all aspects!.\nWylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family friendly in all aspects!\nCompetitive Pay- starting at $25-$26+ per hour based on experience\nJob Type: Full-time/Part-Time\nJob Type: Full-time\nPay: From $25-$26+ per hour based on experience\nBenefits:\n    Employee discount\n\    Paid time off\nSchedule:\n    10 hour shift\n\    8 hour shift\n\    Every weekend\n\    Holidays\n\    Monday to Friday\n\    Weekend availability\nEducation:\n    High school or equivalent (Preferred)\nExperience:\n    cooking: 1 year (Preferred)\nWork Location: One location\nJob Type: Full-time\nPay: $25.00 - $26.00 per hour\nBenefits:\n    Employee discount\n\    Paid time off\nPhysical setting:\n    Casual dining restaurant\nSchedule:\n    8 hour shift\n\    Day shift\n\    Holidays\n\    Monday to Friday\n\    Night shift\n\    Weekend availability\nEducation:\n    High school or equivalent (Preferred)\nExperience:\n    Restaurant: 1 year (Required)";
    const TA = document.createElement("textarea");
    TA.id = "text-area"; // NOTE(cjb): also working id...
    TA.value = DEBUGText;
    TA.style.display = "none";
    TA.addEventListener("blur", () => //TODO(cjb): fix me... <span> wrapping for multiple matches
    {
        TA.style.display = "none";
        PreText.style.display = "inline-block";

        const TextAreaText = TA.value;
        PreText.innerHTML = TextAreaText.slice(0, TA.selectionStart) +
                            `<span class="noice">` +
                            TextAreaText.slice(TA.selectionStart, TA.selectionEnd) +
                            `</span>` + TextAreaText.slice(TA.selectionEnd);

        // NOTE(cjb): There should allways be a last selected pattern input, unless
        // there are no inputs.
        const OptLSPI = LastSelectedPatternInput();
        if (OptLSPI == null)
            return;

        const LSPI = (OptLSPI as HTMLInputElement);
        LSPI.setAttribute("SO", `${TA.selectionStart}`);
        LSPI.setAttribute("EO", `${TA.selectionEnd}`);
        LSPI.value = Regexify(TextAreaText.slice(TA.selectionStart, TA.selectionEnd));
    });
    ABox.appendChild(TA);

    const PreText = document.createElement("pre");
    PreText.setAttribute("tabIndex", "0");
    PreText.id = "pre-text"; // working id name...
    PreText.innerHTML = DEBUGText;
    PreText.addEventListener("keydown", (E: Event) =>
    {
        if ((E as KeyboardEvent).key === "Enter")
        {
            // Toggle TA selection
            PreText.style.display = "none";
            TA.style.display = "inline-block";
            TA.focus();
        }
    });
    PreText.onclick = () =>
    {
        // Toggle TA selection
        PreText.style.display = "none";
        TA.style.display = "inline-block";
        TA.focus();
    }
    ABox.appendChild(PreText);

    const ExtrDefsContainer = document.createElement("div");
    ExtrDefsContainer.id = "extr-defs-container";
    AContainer.appendChild(ExtrDefsContainer);

    const DocSectionsContainer = document.createElement("div");
    DocSectionsContainer.id = "doc-sections-container";
    AContainer.appendChild(DocSectionsContainer);


    const AutoCompleteMenu = document.createElement("menu");
    AutoCompleteMenu.id = "auto-complete-menu";
    AContainer.appendChild(AutoCompleteMenu);

    const DEBUGSelected = document.createElement("p");
    DEBUGSelected.className = "bottomleft";
    document.addEventListener("keyup", (E: Event) => {
        if ((E as KeyboardEvent).key === "Tab")
        {
            if (E.target !== null)
            {
                const LocalName = (E.target as HTMLElement).localName;
                const ClassName = (E.target as HTMLElement).className;
                DEBUGSelected.innerText = `${LocalName}.${ClassName}`;
            }
        }
    });
    AContainer.appendChild(DEBUGSelected);

    // Ascii fox by Brian Kendig
    const AsciiFox4Motivation = document.createElement("pre");
    AsciiFox4Motivation.className = "bottomright";
    AsciiFox4Motivation.innerText = `
       |\\/|    ____
    .__.. \\   /\\  /
     \\_   /__/  \\/
     _/  __   __/
    /___/____/
    v0.4.1-alpha
    `;
    AContainer.appendChild(AsciiFox4Motivation);
}); // GetPyModule
