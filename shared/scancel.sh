#!/bin/bash

master_job=${SLURM_JOBID}.${SLURM_STEPID}

for job in $(squeue --format="%18i" --user=$USER --job=$SLURM_JOBID --steps --nohead); do
    if [[ "$job" != "$master_job" ]] && \
	   [[ "$job" != "${SLURM_JOBID}.Extern" ]] && \
	   [[ "$job" != "${SLURM_JOBID}.Batch" ]]; then
	echo "To scancel step: $job"
	scancel $job 2>&1 
    fi
done

