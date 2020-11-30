#!/bin/bash

set -eu

# Load input parser functions
setup=$( cd "$(dirname "$0")" ; pwd )
. "${setup}/setUpMPP.sh"
. "${DBN_Libraries}/newopts.shlib" "$@"

get_subjList() {
    file_or_list=$1
    subjList=""
    # If a file with the subject ID was passed
    if [ -f "$file_or_list" ] ; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            subjList="$subjList $line"
        done < "$file_or_list"
    # Instead a list was passed
    else
        subjList="$file_or_list"
    fi

    # Sort subject list
    IFS=$'\n' # only word-split on '\n'
    subjList=( $( printf "%s\n" ${subjList[@]} | sort -n) ) # sort
    IFS=$' \t\n' # restore the default
    unset file_or_list
}

# This function gets called by opts_ParseArguments when --help is specified
usage() {
    # header text
    echo "
$log_ToolName: Submitting script for running MPP on Slurm managed computing clusters

Usage: $log_ToolName
                    [--job-name=<name for job allocation>] default=RFLab
                    [--partition=<request a specific partition>] default=workstation
                    [--exclude=<node(s) to be excluded>] default=""
                    [--nodes=<minimum number of nodes allocated to this job>] default="1"
                    [--time=<limit on the total run time of the job allocation>] default="1"
                    [--ntasks=<maximum number of tasks>] default=1
                    [--mem=<specify the real memory required per node>] default=2gb
                    [--export=<export environment variables>] default=ALL
                    [--mail-type=<type of mail>] default=FAIL,END
                    [--mail-user=<user email>] default=eduardojdiniz@gmail.com

                    --studyFolder=<path>                Path to folder with subject images
                    --subjects=<path or list>           File path or list with subject IDs
                    [--class=<3T|7T|T1w_MPR|T2w_SPC>]   Name of the class
                    [--domainX=<3T|7T|T1w_MPR|T2w_SPC>] Name of the domain X
                    [--domainY=<3T|7T|T1w_MPR|T2w_SPC>] Name of the domain Y
                    [--brainSize=<int>]                 Brain size estimate in mm, default 150 for humans
                    [--windowSize=<int>]                window size for bias correction, default 30.
                    [--brainExtractionMethod=<RPP|SPP>] Registration (Segmentation) based brain extraction
                    [--MNIRegistrationMethod=<nonlinear|linear>] Do (not) use FNIRT for image registration to MNI
                    [--custombrain=<NONE|MASK|CUSTOM>] If you have created a custom brain mask saved as
                                                       '<subject>/<domainX>/custom_bc_brain_mask.nii.gz', specify 'MASK'.
                                                       If you have created custom structural images, e.g.:
                                                       - '<subject>/<domainX>/<domainX>_bc.nii.gz'
                                                       - '<subject>/<domainX>/<domainX>_bc_brain.nii.gz'
                                                       - '<subject>/<domainX>/<domainY>_bc.nii.gz'
                                                       - '<subject>/<domainX>/<domainY>_bc_brain.nii.gz'
                                                       to be used when peforming MNI152 Atlas registration, specify
                                                       'CUSTOM'. When 'MASK' or 'CUSTOM' is specified, only the
                                                        AtlasRegistration step is run.
                                                        If the parameter is omitted or set to NONE (the default),
                                                        standard image processing will take place.
                                                        NOTE: This option allows manual correction of brain images
                                                        in cases when they were not successfully processed and/or
                                                        masked by the regular use of the pipelines.
                                                        Before using this option, first ensure that the pipeline
                                                        arguments used were correct and that templates are a good
                                                        match to the data.
                    [--printcom=command]                if 'echo' specified, will only perform a dry run.
        PARAMETERs are [ ] = optional; < > = user supplied value

        Values default to running the example with sample data
    "
    # automatic argument descriptions
    opts_ShowArguments
}


input_parser() {
    opts_AddOptional '--job-name' 'jobName' 'name for job allocation' "an optional value; specify a name for the job allocation. Default: RFLab" "RFLab"
    opts_AddOptional '--partition' 'partition' 'request a specifi partition' "an optional value; request a specific partition for the resource allocation (e.g. standard, workstation). Default: standard" "standard"
    opts_AddOptional  '--exclude' 'exclude' 'node to be excluded' "an optional value; Explicitly exclude certain nodes from the resources granted to the job. Default: None" ""
    opts_AddOptional  '--nodes' 'nodes' 'minimum number of nodes allocated to this job' "an optional value; iIf a job node limit exceeds the number of nodes configured in the partiition, the job will be rejected. Default: 1" "1"
    opts_AddOptional  '--time' 'time' 'limit on the total run time of the job allocation' "an optional value; When the time limit is reached, each task in each job step is sent SIGTERM followed by SIGKILL. Format: days-hours:minutes:seconds. Default 2 hours: None" "0-05:00:00"
    opts_AddOptional '--ntasks' 'nTasks' 'maximum number tasks' "an optional value; sbatch does not launch tasks, it requests an allocation of resources and submits a batch script. This option advises the Slurm controller that job steps run within the allocation will launch a maximum of number tasks and to provide for sufficient resources. Default: 1" "1"
    opts_AddOptional  '--mem' 'mem' 'specify the real memory requried per node' "an optional value; specify the real memory required per node. Default: 2gb" "2gb"
    opts_AddOptional  '--export' 'export' 'export environment variables' "an optional value; Identify which environment variables from the submission environment are propagated to the launched application. Note that SLURM_* variables are always propagated. Default: All of the users environment will be loaded (either from callers environment or clean environment" "ALL"
    opts_AddOptional  '--mail-type' 'mailType' 'type of mail' "an optional value; notify user by email when certain event types occur. Default: FAIL,END" "FAIL,END"
    opts_AddOptional  '--mail-user' 'mailUser' 'user email' "an optional value; User to receive email notification of state changes as defined by --mail-type. Default: eduardojdiniz@gmail.com" "eduardojdiniz@gmail.com"

    opts_AddMandatory '--studyFolder' 'studyFolder' 'raw data folder path' "a required value; is the path to the study folder holding the raw data. Don't forget the study name (e.g. /mnt/storinator/edd32/data/raw/ADNI)"
    opts_AddMandatory '--subjects' 'subjects' 'path to file with subject IDs' "an required value; path to a file with the IDs of the subject to be processed (e.g. /mnt/storinator/edd32/data/raw/ADNI/subjects.txt)" "--subject" "--subjectList" "--subjList"
    opts_AddOptional  '--class' 'class' 'Class Name' "an optional value; is the name of the class. Default: 3T. Supported: 3T | 7T | T1w_MPR | T2w_SPC" "3T"
    opts_AddOptional  '--domainX' 'domainX' 'Domain X' "an optional value; is the name of the domain X. Default: T1w_MPR. Supported: 3T | 7T | T1w_MPR | T2w_SPC" "T1w_MPR"
    opts_AddOptional  '--domainY' 'domainY' 'Domain Y' "an optional value; is the name of the domain Y. Default: T2w_SPC. Supported: 3T | 7T | T1w_MPR | T2w_SPC" "T2w_SPC"
    opts_AddOptional  '--windowSize'  'windowSize' 'window size for bias correction' "an optional value; window size for bias correction; for 7T MRI, the optimal value ranges between 20 and 30. Default: 30." "30"
    opts_AddOptional '--brainSize' 'brainSize' 'Brain Size' "an optional value; the average brain size in mm. Default: 150." "150"
    opts_AddOptional '--customBrain'  'CustomBrain' 'If custom mask or structural images provided' "an optional value; If you have created a custom brain mask saved as <subject>/<domainX>/custom_brain_mask.nii.gz, specify MASK. If you have created custom structural images, e.g.: '<subject>/<domainX>/<domainX>_bc.nii.gz - '<subject>/<domainX>/<domainX>_bc_brain.nii.gz - '<subject>/<domainY>/<domainY>_bc.nii.gz - '<subject>/<domainY>/<domainY>_bc_brain.nii.gz' to be used when peforming MNI152 Atlas registration, specify CUSTOM. When MASK or CUSTOM is specified, only the AtlasRegistration step is run. If the parameter is omitted or set to NONE (the default), standard image processing will take place. NOTE: This option allows manual correction of brain images in cases when they were not successfully processed and/or masked by the regular use of the pipelines. Before using this option, first ensure that the pipeline arguments used were correct and that templates are a good match to the data. Default: NONE. Supported: NONE | MASK| CUSTOM." "NONE"
    opts_AddOptional  '--brainExtractionMethod'  'BrainExtractionMethod' 'Registration (Segmentation) based brain extraction method' "an optional value; The method used to perform brain extraction. Default: RPP. Supported: RPP | SPP." "RPP"
    opts_AddOptional  '--MNIRegistrationMethod'  'MNIRegistrationMethod' '(non)linear registration to MNI' "an optional value; if it is set then only an affine registration to MNI is performed, otherwise, a nonlinear registration to MNI is performed. Default: linear. Supported: linear | nonlinear." "linear"
    opts_AddOptional  '--printcom' 'RUN' 'do (not) perform a dray run' "an optional value; If RUN is not a null or empty string variable, then this script and other scripts that it calls will simply print out the primary commands it otherwise would run. This printing will be done using the command specified in the RUN variable, e.g., echo" "" "--PRINTCOM" "--printcom"


    opts_ParseArguments "$@"

    # Get an index for each subject ID; It will be used to submit an array job
    get_subjList $subjects
    delim=""
    array=""
    i=1
    for id in $subjList ; do
        array="$array$delim$i"
        delim=","
		i=$(($i+1))
    done

    # Display the parsed/default values
    opts_ShowValues

    # Make slurm logs directory
    mkdir -p "$(dirname "$0")"/logs/slurm

    studyName="$(basename -- $studyFolder)"

	queuing_command="sbatch \
        --job-name=${studyName}_${BrainExtractionMethod}_${MNIRegistrationMethod}_${class}_${jobName} \
        --partition=$partition \
        --exclude=$exclude \
        --nodes=$nodes \
        --time=$time \
        --ntasks=$nTasks \
        --export=$export \
        --mail-type=$mailType \
        --mail-user=$mailUser \
        --mem=$mem \
        --array=$array"

    ${queuing_command} CRC.sh \
          --studyFolder=$studyFolder \
          --subjects=$subjects \
          --class=$class \
          --domainX=$domainX \
          --domainY=$domainY \
          --windowSize=$windowSize \
          --customBrain="$CustomBrain" \
          --MNIRegistrationMethod=$MNIRegistrationMethod \
          --brainExtractionMethod=$BrainExtractionMethod \
          --printcom=$RUN
}

input_parser "$@"
