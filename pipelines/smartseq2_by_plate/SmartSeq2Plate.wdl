import "SmartSeq2SingleSample.wdl" as single_cell_run
import "SmartSeq2PlateAggregation.wdl" as ss2_plate_aggregation
       
workflow RunSmartSeq2ByPlate {
  meta {
    description: "The RunSmartSeq2ByPlate pipeline runs multiple SS2 samples in a single pipeline invocation"
  }

  # Version of this pipeline
  String version = "RunSmartSeq2ByPlate_v0.0.1"

  # Gene Annotation
  File genome_ref_fasta
  File rrna_intervals
  File gene_ref_flat

  # Reference index information
  File hisat2_ref_name
  File hisat2_ref_trans_name
  File hisat2_ref_index
  File hisat2_ref_trans_index
  File rsem_ref_index

  # Sample information
  String stranded
  String file_prefix
  Array[String] input_file_names
  String batch_id
  Boolean paired_end

  # Parameter metadata information
  parameter_meta {
    genome_ref_fasta: "Genome reference in fasta format"
    rrna_intervals: "rRNA interval file required by Picard"
    gene_ref_flat: "Gene refflat file required by Picard"
    hisat2_ref_name: "HISAT2 reference index name"
    hisat2_ref_trans_name: "HISAT2 transcriptome index file name"
    hisat2_ref_index: "HISAT2 reference index file in tarball"
    hisat2_ref_trans_index: "HISAT2 transcriptome index file in tarball"
    rsem_ref_index: "RSEM reference index file in tarball"
    stranded: "Library strand information example values: FR RF NONE"
    file_prefix: "Prefix for the fastq files"
    input_file_names: "Array of filename prefixes, will be appended with _1.fastq.gz and _2.fastq.gz"
    batch_id: " Identifier for the batch"
    paired_end: "Is the sample paired end or not"
  }

  ### Execution starts here ###
  # Run the SS2 pipeline for each cell in a scatter
  scatter(idx in range(length(input_file_names))) { 
    call single_cell_run.SmartSeq2SingleCell as sc {
      input:
        fastq1 = file_prefix + '/' + input_file_names[idx] + "_1.fastq.gz",
        fastq2 = file_prefix + '/' + input_file_names[idx] + "_2.fastq.gz", 
        stranded = stranded,
        genome_ref_fasta = genome_ref_fasta,
        rrna_intervals = rrna_intervals,
        gene_ref_flat = gene_ref_flat,
        hisat2_ref_index = hisat2_ref_index,
        hisat2_ref_name = hisat2_ref_name,
        hisat2_ref_trans_index = hisat2_ref_trans_index,
        hisat2_ref_trans_name = hisat2_ref_trans_name,
        rsem_ref_index = rsem_ref_index,
        sample_name = input_file_names[idx],
        output_name = input_file_names[idx],
        paired_end = paired_end,
        output_zarr = true
   }
  }

  ## Aggregate the gene counts
  call ss2_plate_aggregation.AggregateDataMatrix as AggregateGene {
    input:
      filename_array = sc.rsem_gene_results,
        col_name = "est_counts",
        output_name = batch_id+"_gene_est_counts.csv",
  }

  ## Aggregate the Isoform counts
  call ss2_plate_aggregation.AggregateDataMatrix as AggregateIsoform {
      input:
        filename_array = sc.rsem_isoform_results,
        col_name = "tpm",
        output_name = batch_id+"_isoform_tpm.csv",
  }
  
  ### Row metrics ###  
  Array[Array[File]] row_metrics = [ sc.rna_metrics ]
  Array[String] row_metrics_names = [ "rna_metrics" ]
  scatter(i in range(length(row_metrics))){
    call ss2_plate_aggregation.AggregateQCMetrics as AggregateRow {
      input:
        metric_files = row_metrics[i],
        output_name = batch_id+"_"+row_metrics_names[i],
        run_type = "Picard",
    }
  }

  ### Table Metrics ###  
  Array[Array[File]] table_metrics = [ sc.bait_bias_summary_metrics ]
  Array[String] table_metrics_names = [ "bait_bias_summary_metrics" ]
  scatter(i in range(length(table_metrics))){
    call ss2_plate_aggregation.AggregateQCMetrics as AppendTable {
      input:
        metric_files = table_metrics[i],
        output_name = batch_id+"_"+table_metrics_names[i],
        run_type = "PicardTable"
    }
  }

  ### Aggregate QC Metrics ###
  call ss2_plate_aggregation.AggregateQCMetrics as AggregateCore {
    input:
      metric_files = AggregateRow.aggregated_result,
      output_name = batch_id+"_"+"QCs",
      run_type = "Core"
  }

  ### Aggregate the Zarr Files Directly ###
  call ss2_plate_aggregation.AggregateSmartSeq2Zarr as AggregateZarr {
    input:
      zarr_input = sc.zarr_output_files,
      output_file_name = batch_id
  }

  ### Pipeline output ###
  output {
    # Bam files and their indexes
    Array[File] bam_files = sc.aligned_bam
    Array[File] bam_index_files = sc.bam_index

    # Picard merged QC
    File core_QC = AggregateCore.aggregated_result
    Array[File] qc_tables = AppendTable.aggregated_result

    # Isoform and gene matrix
    File gene_matrix = AggregateGene.aggregated_result
    File isoform_matrix = AggregateIsoform.aggregated_result

    File dummy_output = AggregateZarr.dummy_output
  }
}  
