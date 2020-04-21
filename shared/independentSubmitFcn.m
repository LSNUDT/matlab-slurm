function independentSubmitFcn(cluster, job, environmentProperties)
%INDEPENDENTSUBMITFCN Submit a MATLAB job to a Slurm cluster
%
% Set your cluster's PluginScriptsLocation to the parent folder of this
% function to run it when you submit an independent job.
%
% See also parallel.cluster.generic.independentDecodeFcn.

% Copyright 2010-2019 The MathWorks, Inc.

% Store the current filename for the errors, warnings and dctSchedulerMessages
currFilename = mfilename;
if ~isa(cluster, 'parallel.Cluster')
    error('parallelexamples:GenericSLURM:NotClusterObject', ...
        'The function %s is for use with clusters created using the parcluster command.', currFilename)
end

decodeFunction = 'parallel.cluster.generic.independentDecodeFcn';

if ~cluster.HasSharedFilesystem
    error('parallelexamples:GenericSLURM:NotSharedFileSystem', ...
        'The function %s is for use with shared filesystems.', currFilename)
end


if ~strcmpi(cluster.OperatingSystem, 'unix')
    error('parallelexamples:GenericSLURM:UnsupportedOS', ...
        'The function %s only supports clusters with unix OS.', currFilename)
end

enableDebug = 'false';
if isprop(cluster.AdditionalProperties, 'EnableDebug') ...
        && islogical(cluster.AdditionalProperties.EnableDebug) ...
        && cluster.AdditionalProperties.EnableDebug
    enableDebug = 'true';
end

% The job specific environment variables
% Remove leading and trailing whitespace from the MATLAB arguments
matlabArguments = strtrim(environmentProperties.MatlabArguments);
variables = {'PARALLEL_SERVER_DECODE_FUNCTION', decodeFunction; ...
    'PARALLEL_SERVER_STORAGE_CONSTRUCTOR', environmentProperties.StorageConstructor; ...
    'PARALLEL_SERVER_JOB_LOCATION', environmentProperties.JobLocation; ...
    'PARALLEL_SERVER_MATLAB_EXE', environmentProperties.MatlabExecutable; ...
    'PARALLEL_SERVER_MATLAB_ARGS', matlabArguments; ...
    'PARALLEL_SERVER_DEBUG', enableDebug; ...
    'MLM_WEB_LICENSE', environmentProperties.UseMathworksHostedLicensing; ...
    'MLM_WEB_USER_CRED', environmentProperties.UserToken; ...
    'MLM_WEB_ID', environmentProperties.LicenseWebID; ...
    'PARALLEL_SERVER_LICENSE_NUMBER', environmentProperties.LicenseNumber; ...
    'PARALLEL_SERVER_STORAGE_LOCATION', environmentProperties.StorageLocation};

% Deduce the correct quote to use based on the OS of the current machine
if ispc
    quote = '"';
else
    quote = '''';
end

% The local job directory
localJobDirectory = cluster.getJobFolder(job);

% The script name is independentJobWrapper.sh
scriptName = 'independentJobWrapper.sh';
% The wrapper script is in the same directory as this file
dirpart = fileparts(mfilename('fullpath'));
quotedScriptName = sprintf('%s%s%s', quote, fullfile(dirpart, scriptName), quote);

% Get the tasks for use in the loop
tasks = job.Tasks;
numberOfTasks = environmentProperties.NumberOfTasks;
jobIDs = cell(numberOfTasks, 1);
isTaskPending = cellfun(@isempty, get(tasks, {'Error'}));
taskIDs = get(tasks, {'ID'});

% Loop over every task we have been asked to submit
for ii = 1:numberOfTasks
    if ~isTaskPending(ii)
        % Task has been cancelled prior to submission
        continue;
    end
    taskLocation = environmentProperties.TaskLocations{ii};
    % Add the task location to the environment variables
    environmentVariables = [variables; ...
        {'PARALLEL_SERVER_TASK_LOCATION', taskLocation}];
    
    % Choose a file for the output. Please note that currently, JobStorageLocation refers
    % to a directory on disk, but this may change in the future.
    logFile = cluster.getLogLocation(tasks(ii));
    quotedLogFile = sprintf('%s%s%s', quote, logFile, quote);
    
    % Submit one task at a time
    jobName = sprintf('Job%d.%d', job.ID, taskIDs{ii});
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% CUSTOMIZATION MAY BE REQUIRED %%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    additionalSubmitArgs = sprintf('--ntasks=1 --cpus-per-task=%d', cluster.NumThreads);
    commonSubmitArgs = getCommonSubmitArgs(cluster);
    if ~isempty(commonSubmitArgs) && ischar(commonSubmitArgs)
        additionalSubmitArgs = strtrim([additionalSubmitArgs, ' ', commonSubmitArgs]);
    end
    % Create a script to submit a Slurm job - this will be created in the job directory
    dctSchedulerMessage(5, '%s: Generating script for task %i', currFilename, ii);
    localScriptName = tempname(localJobDirectory);
    createSubmitScript(localScriptName, jobName, quotedLogFile, quotedScriptName, ...
        environmentVariables, additionalSubmitArgs);
    % Create the command to run
    commandToRun = sprintf('sh %s', localScriptName);
    
    % Now ask the cluster to run the submission command
    dctSchedulerMessage(4, '%s: Submitting job using command:\n\t%s', currFilename, commandToRun);
    try
        % Make the shelled out call to run the command.
        [cmdFailed, cmdOut] = system(commandToRun);
    catch err
        cmdFailed = true;
        cmdOut = err.message;
    end
    if cmdFailed
        error('parallelexamples:GenericSLURM:SubmissionFailed', ...
            'Submit failed with the following message:\n%s', cmdOut);
    end
    
    dctSchedulerMessage(1, '%s: Job output will be written to: %s\nSubmission output: %s\n', currFilename, logFile, cmdOut);
    jobIDs{ii} = extractJobId(cmdOut);
    
    if isempty(jobIDs{ii})
        warning('parallelexamples:GenericSLURM:FailedToParseSubmissionOutput', ...
            'Failed to parse the job identifier from the submission output: "%s"', ...
            cmdOut);
    end
end

nonEmptyID = ~cellfun(@isempty, jobIDs);
set(tasks(nonEmptyID), 'SchedulerID', convertCharsToStrings(jobIDs(nonEmptyID)));

cluster.setJobClusterData(job, struct('type', 'generic'));
