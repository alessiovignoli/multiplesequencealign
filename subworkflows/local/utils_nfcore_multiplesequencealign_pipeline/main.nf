//
// Subworkflow with functionality specific to the nf-core/multiplesequencealign pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFVALIDATION_PLUGIN } from '../../nf-core/utils_nfvalidation_plugin'
include { paramsSummaryMap          } from 'plugin/nf-validation'
include { fromSamplesheet           } from 'plugin/nf-validation'
include { UTILS_NEXTFLOW_PIPELINE   } from '../../nf-core/utils_nextflow_pipeline'
include { completionEmail           } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary         } from '../../nf-core/utils_nfcore_pipeline'
include { dashedLine                } from '../../nf-core/utils_nfcore_pipeline'
include { nfCoreLogo                } from '../../nf-core/utils_nfcore_pipeline'
include { imNotification            } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE     } from '../../nf-core/utils_nfcore_pipeline'
include { workflowCitation          } from '../../nf-core/utils_nfcore_pipeline'

/*
========================================================================================
    SUBWORKFLOW TO INITIALISE PIPELINE
========================================================================================
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    help              // boolean: Display help text
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args //  array: List of positional nextflow CLI args
    outdir            //  string: The output directory where the results will be saved
    input             //  string: Path to input samplesheet
    tools             //  string: Path to input tools samplesheet

    main:

    ch_versions = Channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //
    pre_help_text = nfCoreLogo(monochrome_logs)
    post_help_text = '\n' + workflowCitation() + '\n' + dashedLine(monochrome_logs)
    def String workflow_command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input samplesheet.csv --outdir <OUTDIR>"
    UTILS_NFVALIDATION_PLUGIN (
        help,
        workflow_command,
        pre_help_text,
        post_help_text,
        validate_params,
        "nextflow_schema.json"
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
        nextflow_cli_args
    )
    //
    // Custom validation for pipeline parameters
    //
    validateInputParameters()

    //
    // Create channel from input file provided through params.input
    //
    ch_input = Channel.fromSamplesheet('input')
    ch_tools = Channel.fromSamplesheet('tools')
                .map {
                    meta ->
                        def meta_clone = meta[0].clone()
                        def tree_map = [:]
                        def align_map = [:]

                        tree_map["tree"] = meta_clone["tree"]
                        tree_map["args_tree"] = meta_clone["args_tree"]
                        tree_map["args_tree_clean"] = Utils.cleanArgs(meta_clone.args_tree)

                        align_map["aligner"] = meta_clone["aligner"]
                        align_map["args_aligner"] = Utils.check_required_args(meta_clone["aligner"], meta_clone["args_aligner"])
                        align_map["args_aligner_clean"] = Utils.cleanArgs(align_map["args_aligner"])

                        [ tree_map, align_map ]
                }

    emit:
    samplesheet = ch_input
    tools       = ch_tools
    versions    = ch_versions
}

/*
========================================================================================
    SUBWORKFLOW FOR PIPELINE COMPLETION
========================================================================================
*/

workflow PIPELINE_COMPLETION {

    take:
    email            //  string: email address
    email_on_fail    //  string: email address sent on pipeline failure
    plaintext_email  // boolean: Send plain-text email instead of HTML
    outdir           //    path: Path to output directory where results will be published
    monochrome_logs  // boolean: Disable ANSI colour codes in log output
    hook_url         //  string: hook URL for notifications
    multiqc_report   //  string: Path to MultiQC report
    shiny_dir_path   //  string: Path to shiny stats file
    trace_dir_path   //  string: Path to trace file
    shiny_trace_mode // string: Mode to use for shiny trace file (default: "latest", options: "latest", "all")

    main:

    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")

    //
    // Completion email and summary
    //
    workflow.onComplete {
        if (email || email_on_fail) {
            completionEmail(summary_params, email, email_on_fail, plaintext_email, outdir, monochrome_logs, multiqc_report.toList())
        }

        completionSummary(monochrome_logs)

        if (hook_url) {
            imNotification(summary_params, hook_url)
        }

        if (shiny_trace_mode) {
            getTraceForShiny(trace_dir_path, shiny_dir_path, shiny_trace_mode)
        }

    }
}


/*
========================================================================================
    FUNCTIONS
========================================================================================
*/
//
// Check and validate pipeline parameters
//
def validateInputParameters() {
    statsParamsWarning()
    evalParamsWarning()
}

//
// Validate channels from input samplesheet
//
def validateInputSamplesheet(input) {
    def (metas, fastqs) = input[1..2]

    // Check that multiple runs of the same sample are of the same datatype i.e. single-end / paired-end
    def endedness_ok = metas.collect{ it.single_end }.unique().size == 1
    if (!endedness_ok) {
        error("Please check input samplesheet -> Multiple runs of a sample must be of the same datatype i.e. single-end or paired-end: ${metas[0].id}")
    }

    return [ metas[0], fastqs ]
}

//
// Warning if incorrect combination of stats parameters are used
//
def statsParamsWarning() {
    if (params.skip_stats){
        if(params.calc_sim || params.calc_seq_stats) {
            def warning_string = "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
                "  WARNING: The param skip_stats is set to '${params.skip_stats}'.\n" +
                "  The following params have values calc_sim: ${params.calc_sim} and calc_seq_stats: ${params.calc_seq_stats} \n" +
                "  As skip_stats is set to true, the params.calc_sim and params.calc_seq_stats will be set by default to false. \n" +
                "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            println(warning_string)
        }
    }
    if (!params.skip_stats && !params.calc_sim && !params.calc_seq_stats){
        params.skip_stats = true
        def warning_string = "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
                "  WARNING: The param skip_stats has been changed from false to true'.\n" +
                "  None of the modules withing the stats subworkflow was activated.  \n" +
                "  To activate them you can use param.calc_sim, params.calc_seq_stats.  \n" +
                "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        println(warning_string)
    }
}

//
// Warning if incorrect combination of eval parameters are used
//
def evalParamsWarning() {
    if (params.skip_eval){
        if(params.calc_sp || params.calc_tc || params.calc_irmsd) {
            def warning_string = "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
                "  WARNING: The param skip_eval is set to '${params.skip_eval}'.\n" +
                "  The following params have values params.calc_sp: ${params.calc_sp}, params.calc_tc: ${params.calc_tc} and params.calc_irms: ${params.calc_irmsd} \n" +
                "  As skip_eval is set to true, the params.calc_sp, params.calc_tc and params.calc_irmsd are set by default to false. \n" +
                "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            println(warning_string)
        }
    }
    if (!params.skip_eval && !params.calc_sp && !params.calc_tc && !params.calc_irmsd ){
            params.skip_eval = true
            def warning_string = "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
                    "  WARNING: The param skip_eval has been changed from false to true'.\n" +
                    "  None of the modules withing the stats subworkflow was activated.  \n" +
                    "  To activate them you can use param.calc_sp, params.calc_tc, params.calc_irmsd.  \n" +
                    "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            println(warning_string)
    }
}

//
// Generate methods description for MultiQC
//
def toolCitationText() {
    // TODO nf-core: Optionally add in-text citation tools to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "Tool (Foo et al. 2023)" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def citation_text = [
            "Tools used in the workflow included:",
            "FastQC (Andrews 2010),",
            "MultiQC (Ewels et al. 2016)",
            "."
        ].join(' ').trim()

    return citation_text
}

def toolBibliographyText() {
    // TODO nf-core: Optionally add bibliographic entries to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "<li>Author (2023) Pub name, Journal, DOI</li>" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def reference_text = [
            "<li>Andrews S, (2010) FastQC, URL: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/).</li>",
            "<li>Ewels, P., Magnusson, M., Lundin, S., & Käller, M. (2016). MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics , 32(19), 3047–3048. doi: /10.1093/bioinformatics/btw354</li>"
        ].join(' ').trim()

    return reference_text
}

def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    meta["doi_text"] = meta.manifest_map.doi ? "(doi: <a href=\'https://doi.org/${meta.manifest_map.doi}\'>${meta.manifest_map.doi}</a>)" : ""
    meta["nodoi_text"] = meta.manifest_map.doi ? "": "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = ""
    meta["tool_bibliography"] = ""

    // TODO nf-core: Only uncomment below if logic in toolCitationText/toolBibliographyText has been filled!
    // meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    // meta["tool_bibliography"] = toolBibliographyText()


    def methods_text = mqc_methods_yaml.text

    def engine =  new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}

def getHeader(trace_file){
    // Get the header of the trace file
    def trace_lines = trace_file.readLines()
    def header = trace_lines[0]
    return header
}

def filterTraceForShiny(trace_file){
    // Retain only the lines that contain "COMPLETED" and "MULTIPLESEQUENCEALIGN:ALIGN"
    def trace_lines = trace_file.readLines()
    def shiny_trace_lines = []
    for (line in trace_lines){
        if (line.contains("COMPLETED") && line.contains("MULTIPLESEQUENCEALIGN:ALIGN")){
            shiny_trace_lines.add(line)
        }
    }
    return shiny_trace_lines
}

// if multiple lines have the same name column
// only the one with the latest timestamp will be kept
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

def takeLatestComplete(traceInfos) {

    // colnames and the position of the columns name and start
    colnames = traceInfos.first().split('\t').collect { it.trim() }
    def name_index = colnames.indexOf("name")
    def start_index = colnames.indexOf("start")
    // remove the column name line
    traceInfos = traceInfos.drop(1)
    // Initialize a map to store entries by their names and latest submit timestamps
    def latestEntries = [:]
    def formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS")

    // Iterate over each line
    // If the name is not in the map or the submit timestamp is after the latest one, update the map
    traceInfos.each { line ->
        def values = line.split('\t')
        def name = values[name_index]
        def submit = LocalDateTime.parse(values[start_index], formatter)
        if (!latestEntries.containsKey(name) || submit.isAfter(latestEntries[name][start_index])) {
            latestEntries[name] = values
        }
    }
    def filteredData = colnames.join('\t') + '\n'
    filteredData = filteredData + latestEntries.values().collect { it.join('\t') }.join('\n')
    def result = []
    result.addAll(filteredData)
    return result
}

def getTraceForShiny(trace_dir_path, shiny_dir_path, shiny_trace_mode){
        // According to the mode selected, get either the latest trace file or all trace files
        // If all trace files are selected, it is assumed that the trace files were generated with the "resume" mode
        def trace_dir = new File("${trace_dir_path}")
        def trace_files = []
        if (shiny_trace_mode == "all"){
            trace_files = trace_dir.listFiles().findAll { it.name.startsWith("execution_trace") }
        }
        else if(shiny_trace_mode == "latest"){
            trace_files = trace_dir.listFiles().findAll { it.name.startsWith("execution_trace") }.sort { -it.lastModified() }.take(1)
        }
        else{
            print("Invalid shiny trace mode. Please use either 'latest' or 'all'")
        }
        // Filter the trace files for shiny
        // and move the trace file to the shiny directory
        if (trace_files.size() > 0) {
            def trace_infos = []
            def header_added = false
            for (file in trace_files){
                if( !header_added ){
                    trace_infos = trace_infos + getHeader(file)
                    header_added = true
                }
                trace_infos = trace_infos + filterTraceForShiny(file)
            }
            // if trace infos is empty then print a message
            if(trace_infos.size() == 0){
                print("There is an issue with your trace file!")
            }
            trace_infos = takeLatestComplete(trace_infos)

            def shiny_trace_file = new File("${shiny_dir_path}/trace.txt")
            shiny_trace_file.write(trace_infos.join("\n"))
        }else{
            print("No trace file found in the " + trace_dir_path + " directory.")
        }
}

import nextflow.Nextflow
import groovy.text.SimpleTemplateEngine

class Utils {



    public static cleanArgs(argString) {
        def cleanArgs = argString.toString().trim().replace("  ", " ").replace(" ", "_").replaceAll("==", "_").replaceAll("\\s+", "")
        // if clearnArgs is empty, return ""

        if (cleanArgs == null || cleanArgs == "") {
            return ""
        }else{
            return cleanArgs
        }
    }

    public static fix_args(tool,args,tool_to_be_checked, required_flag, default_value) {
        /*
        This function checks if the required_flag is present in the args string for the tool_to_be_checked.
        If not, it adds the required_flag and the default_value to the args string.
        */
        if(tool == tool_to_be_checked){
            if( args == null || args == ""|| args == "null" || !args.contains(required_flag+" ")){
                if(args == null || args == ""|| args == "null"){
                    args = ""
                }
                args = args + " " + required_flag + " " + default_value
            }
        }
        return args
    }

    public static check_required_args(tool,args){

        // 3DCOFFEE
        args = fix_args(tool,args,"3DCOFFEE", "-method", "TMalign_pair")
        // REGRESSIVE
        args = fix_args(tool,args,"REGRESSIVE", "-reg", "")
        args = fix_args(tool,args,"REGRESSIVE", "-reg_method", "famsa_msa")
        args = fix_args(tool,args,"REGRESSIVE", "-reg_nseq", "1000")
        args = fix_args(tool,args,"REGRESSIVE", "-output", "fasta_aln")
        // TCOFFEE
        args = fix_args(tool,args,"TCOFFEE", "-output", "fasta_aln")

        return args

    }





}
