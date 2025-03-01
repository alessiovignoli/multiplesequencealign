//
// Compute stats about the input sequences
//
include {   CALCULATE_SEQSTATS                             } from '../../modules/local/calculate_seqstats.nf'
include {   PARSE_SIM                                      } from '../../modules/local/parse_sim.nf'
include {   TCOFFEE_SEQREFORMAT as TCOFFEE_SEQREFORMAT_SIM } from '../../modules/nf-core/tcoffee/seqreformat/main.nf'
include {   CSVTK_CONCAT  as CONCAT_SEQSTATS               } from '../../modules/nf-core/csvtk/concat/main.nf'
include {   CSVTK_CONCAT  as CONCAT_SIMSTATS               } from '../../modules/nf-core/csvtk/concat/main.nf'
include {   CSVTK_JOIN    as MERGE_STATS                   } from '../../modules/nf-core/csvtk/join/main.nf'


workflow STATS {
    take:
    ch_seqs                //      channel: meta, /path/to/file.fasta

    main:

    ch_versions = Channel.empty()
    sim_csv = Channel.empty()
    seqstats_csv = Channel.empty()
    stats_summary = Channel.empty()

    // // -------------------------------------------
    // //      SEQUENCE SIMILARITY
    // // -------------------------------------------
    if( params.calc_sim == true){
        TCOFFEE_SEQREFORMAT_SIM(ch_seqs)
        tcoffee_seqreformat_sim = TCOFFEE_SEQREFORMAT_SIM.out.formatted_file
        ch_versions = ch_versions.mix(TCOFFEE_SEQREFORMAT_SIM.out.versions.first())
        tcoffee_seqreformat_simtot = PARSE_SIM(tcoffee_seqreformat_sim)
        ch_versions = ch_versions.mix(PARSE_SIM.out.versions)

        ch_sim_summary = tcoffee_seqreformat_simtot.map{
                                                    meta, csv -> csv
                                                }.collect().map{
                                                    csv -> [ [id:"summary_simstats"], csv]
                                                }
        CONCAT_SIMSTATS(ch_sim_summary, "csv", "csv")
        sim_csv = sim_csv.mix(CONCAT_SIMSTATS.out.csv)
        ch_versions = ch_versions.mix(CONCAT_SIMSTATS.out.versions)
    }

    // -------------------------------------------
    //      SEQUENCE GENERAL STATS
    //      Sequence length, # of sequences, etc
    // -------------------------------------------
    CALCULATE_SEQSTATS(ch_seqs)
    seqstats = CALCULATE_SEQSTATS.out.seqstats
    seqstats_summary = CALCULATE_SEQSTATS.out.seqstats_summary
    ch_versions = ch_versions.mix(CALCULATE_SEQSTATS.out.versions.first())

    ch_seqstats_summary = seqstats_summary.map{
                                                meta, csv -> csv
                                            }.collect().map{
                                                csv -> [ [id:"summary_seqstats"], csv]
                                            }

    CONCAT_SEQSTATS(ch_seqstats_summary, "csv", "csv")
    seqstats_csv = seqstats_csv.mix(CONCAT_SEQSTATS.out.csv)
    ch_versions = ch_versions.mix(CONCAT_SEQSTATS.out.versions)


    // -------------------------------------------
    //      MERGE ALL STATS
    // -------------------------------------------

    sim      = sim_csv.map{ meta, csv -> csv }
    seqstats = seqstats_csv.map{ meta, csv -> csv }

    csvs_stats = sim.mix(seqstats).collect().map{ csvs -> [[id:"summary_stats"], csvs] }
    def number_of_stats = [params.calc_sim, params.calc_seq_stats].count(true)
    if(number_of_stats >= 2){
        MERGE_STATS(csvs_stats)
        ch_versions = ch_versions.mix(MERGE_STATS.out.versions)
        stats_summary = MERGE_STATS.out.csv
    }else if(number_of_stats == 1){
        stats_summary = csvs_stats
    }

    emit:
    stats_summary
    versions         = ch_versions.ifEmpty(null) // channel: [ versions.yml ]
}
