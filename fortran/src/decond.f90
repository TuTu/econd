program decond
  use mpiproc
  use varpars, only: rk
  use manager, only: init_config, read_config, prepare, decompose, output, finish
  implicit none
  real(rk) :: prog_starttime

  call mpi_setup('init')
  prog_starttime = mpi_wtime()

  call init_config()
  call read_config()
  call prepare()
  call decompose()
  call output()
  call finish()

  if (myrank == root) then
    write(*,*)
    write(*,*) "time for the whole program (sec):", mpi_wtime() - prog_starttime
  end if

  call mpi_setup('stop')
  stop
end program decond
