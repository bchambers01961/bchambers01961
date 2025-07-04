xtrabackup_args=(
                    "--defaults-file=.my.cnf"
                    "--backup"
                    "--target-dir=/data/backups/central_adhoc/"
                    "--galera-info"
                    "--parallel=6"
                    "--open-files-limit=5096"
                    "--rsync"

                    )
					
xtrabackup "${xtrabackup_args[@]}"

xtrabackup_args=(
                    "--defaults-file=.my.cnf"
                    "--prepare"
                    "--target-dir=/data/backups/central_adhoc/"
                    )
					
xtrabackup "${xtrabackup_args[@]}"

xtrabackup_args=(
                    "--defaults-file=.my.cnf"
                    "--copy-back"
					"--parallel=6"
                    "--target-dir=/data/backups/central_adhoc/"
                    )
					
xtrabackup "${xtrabackup_args[@]}"