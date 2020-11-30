#!/bin/bash

#SBATCH --error=./logs/slurm/slurm-%A_%a.err
#SBATCH --output=./logs/slurm/slurm-%A_%a.out

# The hostname from which sbatch was invoked (e.g. cluster)
SERVER=$SLURM_SUBMIT_HOST
# The name of the node running the job script (e.g. node10)
NODE=$SLURMD_NODENAME
# The directory from which sbatch was invoked (e.g. proj/DBN/src/data/MPP)
SERVERDIR=$SLURM_SUBMIT_DIR

# This function gets called by opts_ParseArguments when --help is specified
usage() {
    # header text
    echo "
$log_ToolName: Queueing script for running MPP on Slurm-based computing clusters

Usage: $log_ToolName
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
    # Load input parser functions
    . "${SERVERDIR}/setUpMPP.sh"
    . "${DBN_Libraries}/newopts.shlib" "$@"

    opts_AddMandatory '--studyFolder' 'studyFolder' 'raw data folder path' "a required value; is the path to the study folder holding the raw data. Don't forget the study name (e.g. /mnt/storinator/edd32/data/raw/ADNI)"
    opts_AddMandatory '--subjects' 'subjects' 'path to file with subject IDs' "a required value; path to a file with the IDs of the subject to be processed (e.g. /mnt/storinator/edd32/data/raw/ADNI/subjects.txt)" "--subject" "--subjectList" "--subjList"
    opts_AddOptional  '--class' 'class' 'Class Name' "an optional value; is the name of the class. Default: 3T. Supported: 3T | 7T | T1w_MPR | T2w_SPC" "3T"
    opts_AddOptional  '--domainX' 'domainX' 'Domain X' "an optional value; is the name of the domain X. Default: T1w_MPR. Supported: 3T | 7T | T1w_MPR | T2w_SPC" "T1w_MPR"
    opts_AddOptional  '--domainY' 'domainY' 'Domain Y' "an optional value; is the name of the domain Y. Default: T2w_SPC. Supported: 3T | 7T | T1w_MPR | T2w_SPC" "T2w_SPC"
    opts_AddOptional '--windowSize'  'windowSize' 'window size for bias correction' "an optional value; window size for bias correction; for 7T MRI, the optimal value ranges between 20 and 30. Default: 30." "30"
    opts_AddOptional '--brainSize' 'brainSize' 'Brain Size' "an optional value; the average brain size in mm. Default: 150." "150"
    opts_AddOptional '--brainExtractionMethod'  'BrainExtractionMethod' 'Registration (Segmentation) based brain extraction method' "an optional value; The method used to perform brain extraction. Default: RPP. Supported: RPP | SPP." "RPP"
    opts_AddOptional '--MNIRegistrationMethod'  'MNIRegistrationMethod' '(non)linear registration to MNI' "an optional value; if it is set then only an affine registration to MNI is performed, otherwise, a nonlinear registration to MNI is performed. Default: linear. Supported: linear | nonlinear." "linear"
    opts_AddOptional '--customBrain'  'CustomBrain' 'If custom mask or structural images provided' "an optional value; If you have created a custom brain mask saved as <subject>/<domainX>/custom_brain_mask.nii.gz, specify MASK. If you have created custom structural images, e.g.: '<subject>/<domainX>/<domainX>_bc.nii.gz - '<subject>/<domainX>/<domainX>_bc_brain.nii.gz - '<subject>/<domainY>/<domainY>_bc.nii.gz - '<subject>/<domainY>/<domainY>_bc_brain.nii.gz' to be used when peforming MNI152 Atlas registration, specify CUSTOM. When MASK or CUSTOM is specified, only the AtlasRegistration step is run. If the parameter is omitted or set to NONE (the default), standard image processing will take place. NOTE: This option allows manual correction of brain images in cases when they were not successfully processed and/or masked by the regular use of the pipelines. Before using this option, first ensure that the pipeline arguments used were correct and that templates are a good match to the data. Default: NONE. Supported: NONE | MASK| CUSTOM." "NONE"
    opts_AddOptional '--printcom' 'RUN' 'do (not) perform a dray run' "an optional value; If RUN is not a null or empty string variable, then this script and other scripts that it calls will simply print out the primary commands it otherwise would run. This printing will be done using the command specified in the RUN variable, e.g., echo" "" "--PRINTCOM" "--printcom"

    opts_ParseArguments "$@"

    # Display the parsed/default values
    opts_ShowValues
}


setup() {
    SCP=/usr/bin/scp
    SSH=/usr/bin/ssh

    # Looks in the file of IDs and get the correspoding subject ID for this job
    SubjectID=$(head -n $SLURM_ARRAY_TASK_ID "$subjects" | tail -n 1)
    # The directory holding the data for the subject correspoinding ot this job
    SUBJECTDIR=$studyFolder/raw/$SubjectID
    # Node directory that where computation will take place
    NODEDIR=/tmp/work/SLURM_${BrainExtractionMethod}_${MNIRegistrationMethod}_${class}_${SubjectID}_${SLURM_JOB_ID}

    mkdir -p $NODEDIR
    echo Transferring files from server to compute node $NODE

    # Copy MPP scripts from server to node, creating whatever directories required
    $SCP -r $SERVERDIR $NODEDIR

    NCPU=`scontrol show hostnames $SLURM_JOB_NODELIST | wc -l`
    echo ------------------------------------------------------
    echo ' This job is allocated on '$NCPU' cpu(s)'
    echo ------------------------------------------------------
    echo SLURM: sbatch is running on $SERVER
    echo SLURM: server calling directory is $SERVERDIR
    echo SLURM: node is $NODE
    echo SLURM: node working directory is $NODEDIR
    echo SLURM: job name is $SLURM_JOB_NAME
    echo SLURM: master job identifier of the job array is $SLURM_ARRAY_JOB_ID
    echo SLURM: job array index identifier is $SLURM_ARRAY_TASK_ID
    echo SLURM: job identifier-sum master job ID and job array index is $SLURM_JOB_ID
    echo ' '
    echo ' '

    # Copy DATA from server to node, creating whatever directories required
    $SCP -r $SUBJECTDIR $NODEDIR

    # Location of subject folders (named by subjectID)
    studyFolderBasename=`basename $studyFolder`;

    # Report major script control variables to usertart_auto_complete)cho "studyFolder: ${SERVERDATADIR}"
	echo "subject:${SubjectID}"
	echo "environmentScript: setUpMPP.sh"
	echo "class: ${class}"
	echo "domainX: ${domainX}"
	echo "domainY: ${domainY}"
	echo "MNIRegistrationMethod: ${MNIRegistrationMethod}"
    echo "windowSize: ${windowSize}"
	echo "printcom: ${RUN}"

    # Create log folder
    LOGDIR="${NODEDIR}/logs/"
    mkdir -p $LOGDIR

    # Templates

    # Hi resolution domain X MNI template
    xTemplate="${MNI_Templates}/MNI152_T1_0.7mm.nii.gz"
    # Hi resolution brain extracted domain X MNI template
    xTemplateBrain="${MNI_Templates}/MNI152_T1_0.7mm_brain.nii.gz"
    # Low resolution domain X MNI template
    xTemplate2mm="${MNI_Templates}/MNI152_T1_2mm.nii.gz"
    # Hi resolution domain Y MNI template
    yTemplate="${MNI_Templates}/MNI152_T2_0.7mm.nii.gz"
    # Hi resoslution brain extracted domain Y MNI template
    yTemplateBrain="${MNI_Templates}/MNI152_T2_0.7mm_brain.nii.gz"
    # Low resolution domain Y MNI template
    yTemplate2mm="${MNI_Templates}/MNI152_T2_2mm.nii.gz"
    # Hi resolution MNI brain mask template
    TemplateMask="${MNI_Templates}/MNI152_T1_0.7mm_brain_mask.nii.gz"
    # Low resolution MNI brain mask template
    Template2mmMask="${MNI_Templates}/MNI152_T1_2mm_brain_mask_dil.nii.gz"

    # Other Config Settings
    # BrainSize in mm, 150 for humans
    BrainSize="150"
    # FNIRT 2mm T1w Config
    FNIRTConfig="${MPP_Config}/T1_2_MNI152_2mm.cnf"
}

# Join function with a character delimiter
join_by() { local IFS="$1"; shift; echo "$*"; }

main() {
    ###############################################################################
	# Inputs:
	#
	# Scripts called by this script do NOT assume anything about the form of the
	# input names or paths. This batch script assumes the following raw data naming
	# convention, e.g.
	#
	# ${SubjectID}/${class}/${domainX}/${SubjectID}_${class}_${domainY}1.nii.gz
	# ${SubjectID}/${class}/${domainX}/${SubjectID}_${class}_${domainY}2.nii.gz
    # ...
	# ${SubjectID}/${class}/${domainX}/${SubjectID}_${class}_${domainY}n.nii.gz
    ###############################################################################


    # Detect Number of domain X Images and build list of full paths to them
    Xs=($(find ${NODEDIR}/${SubjectID}/${class} -type f | grep "${domainX}.\/${SubjectID}_-_${class}_-_${domainX}.\.nii\.gz$"))
    numXs=`echo "${#Xs[@]}"`
    echo "Found ${numXs} ${domainX} Images for subject ${SubjectID}"
    xInputImages=`join_by '@' ${Xs[@]}`

    # Detect Number of domain Y Images and build list of full paths to them
    Ys=($(find ${NODEDIR}/${SubjectID}/${class} -type f | grep "${domainY}.\/${SubjectID}_-_${class}_-_${domainY}.\.nii\.gz$"))
    numYs=`echo "${#Ys[@]}"`
    echo "Found ${numYs} ${domainY} Images for subject ${SubjectID}"
    yInputImages=`join_by '@' ${Ys[@]}`

    cd $NODEDIR

    # Submit to be run the MPP.sh script with all the specified parameter values
    $NODEDIR/MPP/MPP.sh \
        --studyName="$studyFolderBasename" \
        --subject="$SubjectID" \
        --class=$class \
        --domainX="$domainX" \
        --domainY="$domainY" \
        --x="$xInputImages" \
        --y="$yInputImages" \
        --xTemplate="$xTemplate" \
        --xTemplateBrain="$xTemplateBrain" \
        --xTemplate2mm="$xTemplate2mm" \
        --yTemplate="$yTemplate" \
        --yTemplateBrain="$yTemplateBrain" \
        --yTemplate2mm="$yTemplate2mm" \
        --templateMask="$TemplateMask" \
        --template2mmMask="$Template2mmMask" \
        --brainSize="$BrainSize" \
        --MNIRegistrationMethod="$MNIRegistrationMethod" \
        --windowSize="$windowSize" \
        --customBrain="$CustomBrain" \
        --brainExtractionMethod="$BrainExtractionMethod" \
        --FNIRTConfig="$FNIRTConfig" \
        --printcom=$RUN \
        1> $LOGDIR/$SubjectID.out \
        2> $LOGDIR/$SubjectID.err
}

cleanup() {

    permanent_dir=preprocessed/${BrainExtractionMethod}/${MNIRegistrationMethod}/${class}/${SubjectID}
    log_dir=${studyFolder}/logs/${BrainExtractionMethod}/${MNIRegistrationMethod}/${class}
    slurm_log_dir=${SERVERDIR}/logs/slurm/${BrainExtractionMethod}/${MNIRegistrationMethod}/${class}

    echo ' '
    echo Transferring files from node to server
    echo "Writing files in permanent directory ${studyFolder}/${permanent_dir}"

    mkdir -p ${studyFolder}/${permanent_dir}
    $SCP  -r ${NODEDIR}/${studyFolderBasename}/${permanent_dir}/* ${studyFolder}/${permanent_dir}/

    mkdir -p ${log_dir}
    $SCP  -r ${NODEDIR}/logs/* ${log_dir}/

    mkdir -p ${slurm_log_dir}
    mv $SERVERDIR/logs/slurm/slurm-${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.err ${slurm_log_dir}/slurm-${SubjectID}.err
    mv $SERVERDIR/logs/slurm/slurm-${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out ${slurm_log_dir}/slurm-${SubjectID}.out
    $SCP ${slurm_log_dir}/slurm-${SubjectID}.err ${log_dir}/
    $SCP ${slurm_log_dir}/slurm-${SubjectID}.out ${log_dir}/

    echo ' '
    echo 'Files transfered to permanent directory, clean temporary directory and log files'
    rm -rf /tmp/work/SLURM_${BrainExtractionMethod}_${MNIRegistrationMethod}_${class}_${SubjectID}_${SLURM_JOB_ID}
    rm ${slurm_log_dir}/slurm-${SubjectID}.err
    rm ${slurm_log_dir}/slurm-${SubjectID}.out
}

early() {
	echo ' '
	echo ' ############ WARNING:  EARLY TERMINATION #############'
	echo ' '
}

input_parser "$@"
setup
main
cleanup

trap 'early; cleanup' SIGINT SIGKILL SIGTERM SIGSEGV

# happy end
exit 0
