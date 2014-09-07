program decompose_mpi
  use mpi
  use utility, only : handle
  use xdr, only : open_trajectory, close_trajectory, read_trajectory, get_natom
  use top, only : open_top, close_top, read_top, system, print_sys
  implicit none
  integer, parameter :: NUM_POSITIONAL_ARG = 2, LEAST_REQUIRED_NUM_ARG = 6
  integer :: num_arg, num_subArg, num_argPerMolType
  integer :: i, j, k, n, totNumMol, t, sysNumAtom
  character(len=128) :: outFilename, dataFilename, topFilename, arg
  type(handle) :: dataFileHandle, topFileHandle
  integer :: numFrame, maxLag, num_rBin, stat, numMolType, numFrameRead, numFrame_k
  integer :: molTypePairIndex, molTypePairAllIndex, tmp_i, skip
  integer, allocatable :: charge(:), rBinIndex(:), norm(:), start_index(:)
  real(8) :: cell(3), timestep, rBinWidth, tmp_r, dummy_null
  real(8), allocatable :: pos_tmp(:, :), vel_tmp(:, :), vv(:)
  !one frame data (dim=3, atom) 
  real(8), allocatable :: pos(:, :, :), vel(:, :, :)
  !pos(dim=3, timeFrame, atom), vel(dim=3, timeFrame, atom)
  real(8), allocatable :: time(:), rho(:, :), sdCorr(:, :, :), nCorr(:, :)
  !sdCorr: spatially decomposed correlation (lag, rBin, molTypePairIndex)
  !rho: (num_rBin, molTypePairIndex)
  logical :: is_periodic, is_pa_mode, is_pm_mode, is_sd
  type(system) :: sys

  !MPI variables
  integer :: ierr, nprocs, myrank
  integer:: numDomain_r, numDomain_c, numMolPerDomain_r, numMolPerDomain_c
  integer, parameter :: root = 0
  integer :: r_start, r_end, c_start, c_end
  real(8) :: starttime, endtime, starttime2, prog_starttime
  integer :: r_start_offset, c_start_offset
  integer :: residueMol_r, residueMol_c, num_r, num_c
  real(8), allocatable :: pos_r(:, :, :), pos_c(:, :, :), vel_r(:, :, :), vel_c(:, :, :)
  integer :: row_comm, col_comm, r_group_idx, c_group_idx, offset
  integer, dimension(:), allocatable :: displs_r, displs_c, scounts_r, scounts_c

  !initialize
  call mpi_init(ierr)
  call mpi_comm_size(MPI_COMM_WORLD, nprocs, ierr)
  call mpi_comm_rank(MPI_COMM_WORLD, myrank, ierr)

  prog_starttime = MPI_Wtime()

  num_arg = command_argument_count()
  is_pa_mode = .false.
  is_pm_mode = .false.

  !default values
  outFilename = 'corr.h5'
  skip = 1
  maxLag = -1
  is_sd = .true.
  rBinWidth = 0.01
  numDomain_r = 0
  numDomain_c = 0

  !root checks the number of the input arguments
  is_periodic = .true.
  if (num_arg < LEAST_REQUIRED_NUM_ARG) then
    if (myrank == root) call print_usage()
    call mpi_abort(MPI_COMM_WORLD, 1, ierr);
    call exit(1)
  end if

  !read parameters for all ranks
  i = 1
  do while (i <= num_arg)
    call get_command_argument(number=i, value=arg, status=stat)
    if (i <= NUM_POSITIONAL_ARG) then
      select case (i)
      case (1)
        dataFilename = arg
        i = i + 1
      case (2)
        read(arg, *) numFrame ! in the unit of frame number
        i = i + 1
      case default
        if (myrank == root) then
          write(*,*) "Something is wrong in the codes; maybe NUM_POSITIONAL_ARG is not set correctly."
        end if
        call mpi_abort(MPI_COMM_WORLD, 1, ierr);
        call exit(1)
      end select
    else
      i = i + 1
      select case (arg)
      case ('-pa')
        if (is_pm_mode) then
          if (myrank == root) then
            write(*,*) "-pa and -pm cannot be given at the same time!"
            call print_usage()
          end if
          call mpi_abort(MPI_COMM_WORLD, 1, ierr);
          call exit(1)
        end if
        is_pa_mode = .true.
        call get_command_argument(i, topFilename)
        i = i + 1
        num_subArg = count_arg(i, num_arg)
        num_argPerMolType = 2
        if (mod(num_subArg, num_argPerMolType) > 0 .or. num_subArg < num_argPerMolType) then
          if (myrank == root) then
            write(*,*) "Wrong number of arguments for -pm: ", num_subArg + 1
            call print_usage()
          end if
          call mpi_abort(MPI_COMM_WORLD, 1, ierr);
          call exit(1)
        end if

        numMolType = num_subArg / num_argPerMolType

        allocate(sys%mol(numMolType), stat=stat)
        if (stat /=0) then
          write(*,*) "Allocation failed: sys%mol"
          call mpi_abort(MPI_COMM_WORLD, 1, ierr);
          call exit(1)
        end if 

        allocate(charge(numMolType), stat=stat)
        if (stat /=0) then
          write(*,*) "Allocation failed: charge"
          call mpi_abort(MPI_COMM_WORLD, 1, ierr);
          call exit(1)
        end if 

        allocate(start_index(numMolType), stat=stat)
        if (stat /=0) then
          write(*,*) "Allocation failed: start_index"
          call exit(1)
        end if 

        do n = 1, numMolType
          call get_command_argument(i, sys%mol(n)%type)
          i = i + 1
          call get_command_argument(i, arg)
          read(arg, *) start_index(n)
          i = i + 1
        end do

        if (myrank == root) then
          write(*,*) "sys%mol%type = ", sys%mol%type
          write(*,*) "start_index = ", start_index
        end if

        !read topFile
        topFileHandle = open_top(topFilename)
        call read_top(topFileHandle, sys)
        call close_top(topFileHandle)
        if (myrank == root) call print_sys(sys)

        do n = 1, numMolType
          charge(n) = sum(sys%mol(n)%atom(:)%charge)
        end do
        totNumMol = sum(sys%mol(:)%num)

      case ('-pm')
        if (is_pa_mode) then
          if (myrank == root) then
            write(*,*) "-pa and -pm cannot be given at the same time!"
            call print_usage()
          end if
          call mpi_abort(MPI_COMM_WORLD, 1, ierr);
          call exit(1)
        end if
        is_pm_mode = .true.
        num_subArg = count_arg(i, num_arg)
        num_argPerMolType = 3
        if (mod(num_subArg, num_argPerMolType) > 0 .or. num_subArg < num_argPerMolType) then
          if (myrank == root) then
            write(*,*) "Wrong number of arguments for -pm: ", num_subArg
            call print_usage()
          end if
          call mpi_abort(MPI_COMM_WORLD, 1, ierr);
          call exit(1)
        end if

        numMolType = num_subArg / num_argPerMolType

        allocate(sys%mol(numMolType), stat=stat)
        if (stat /=0) then
          write(*,*) "Allocation failed: sys%mol"
          call mpi_abort(MPI_COMM_WORLD, 1, ierr);
          call exit(1)
        end if 

        allocate(charge(numMolType), stat=stat)
        if (stat /=0) then
          write(*,*) "Allocation failed: charge"
          call mpi_abort(MPI_COMM_WORLD, 1, ierr);
          call exit(1)
        end if 

        do n = 1, numMolType
          call get_command_argument(i, sys%mol(n)%type) 
          i = i + 1
          call get_command_argument(i, arg) 
          i = i + 1
          read(arg, *) charge(n)
          call get_command_argument(i, arg) 
          i = i + 1
          read(arg, *) sys%mol(n)%num
        end do

        totNumMol = sum(sys%mol(:)%num)
        if (myrank == root) then
          write(*,*) "sys%mol%type = ", sys%mol%type
          write(*,*) "charge = ", charge
          write(*,*) "sys%mol%num = ", sys%mol%num
        end if

      case ('-o')
        call get_command_argument(i, outFilename)
        i = i + 1

      case ('-s')
        call get_command_argument(i, arg) 
        i = i + 1
        read(arg, *) skip

      case ('-l')
        call get_command_argument(i, arg) ! in the unit of frame number
        i = i + 1
        read(arg, *) maxLag

      case ('-nosd')
        is_sd = .false.

      case ('-r')
        call get_command_argument(i, arg)
        i = i + 1
        read(arg, *) rBinWidth

      case ('-d')
        num_subArg = 2
        call get_command_argument(i, arg) 
        i = i + 1
        read(arg, *) numDomain_r

        call get_command_argument(i, arg) 
        i = i + 1
        read(arg, *) numDomain_c

      case default
        if (myrank == root) write(*,*) "Unknown argument: ", trim(adjustl(arg))
        call mpi_abort(MPI_COMM_WORLD, 1, ierr)
        call exit(1)
      end select
    end if
  end do

  if (maxLag == -1) then
    maxLag = numFrame - 1
  end if

  !rank root output parameters read
  if (myrank == root) then
    write(*,*) "outFile = ", outFilename
    write(*,*) "inFile.trr = ", dataFilename
    if (is_pa_mode) write(*,*) "topFile.top = ", topFilename
    write(*,*) "numFrame= ", numFrame
    write(*,*) "maxLag = ", maxLag 
    if (is_sd) write(*,*) "rBinWidth = ", rBinWidth
    write(*,*) "numMolType = ", numMolType
    write(*,*) "numDomain_r = ", numDomain_r
    write(*,*) "numDomain_c = ", numDomain_c
  end if

  !domain decomposition for atom pairs (numDomain_r * numDomain_c = nprocs)
  !numMolPerDomain_r * numDomain_r ~= totNumMol
  if (numDomain_r == 0 .and. numDomain_c == 0) then
    numDomain_c = nint(sqrt(dble(nprocs)))
    do while(mod(nprocs, numDomain_c) /= 0)
      numDomain_c = numDomain_c - 1
    end do
    numDomain_r = nprocs / numDomain_c
  else if (numDomain_r > 0) then
    numDomain_c = nprocs / numDomain_r
  else if (numDomain_c > 0) then
    numDomain_c = nprocs / numDomain_r
  else
    write(*,*) "Invalid domain decomposition: ", numDomain_r, " x ", numDomain_c 
    call mpi_abort(MPI_COMM_WORLD, 1, ierr);
    call exit(1)
  end if

  if (numDomain_r * numDomain_c /= nprocs) then
    write(*,*) "Domain decomposition failed: ", numDomain_r, " x ", numDomain_c, " /= ", nprocs
    call mpi_abort(MPI_COMM_WORLD, 1, ierr);
    call exit(1)
  end if 

  !Determine row and column position for the node
  r_group_idx = mod(myrank, numDomain_r) !column-major mapping
  c_group_idx = myrank / numDomain_r

  !Split comm into row and column comms
  call mpi_comm_split(MPI_COMM_WORLD, c_group_idx, r_group_idx, col_comm, ierr)
  !color by row, rank by column
  call mpi_comm_split(MPI_COMM_WORLD, r_group_idx, c_group_idx, row_comm, ierr)
  !color by column, rank by row

  numMolPerDomain_r = totNumMol / numDomain_r
  numMolPerDomain_c = totNumMol / numDomain_c
  residueMol_r = mod(totNumMol, numDomain_r)
  residueMol_c = mod(totNumMol, numDomain_c)

  allocate(displs_r(numDomain_r), stat=stat)
  if (stat /=0) then
    write(*,*) "Allocation failed: displs_r"
    call exit(1)
  end if 
  allocate(displs_c(numDomain_c), stat=stat)
  if (stat /=0) then
    write(*,*) "Allocation failed: displs_c"
    call exit(1)
  end if 
  allocate(scounts_r(numDomain_r), stat=stat)
  if (stat /=0) then
    write(*,*) "Allocation failed: scounts_r"
    call exit(1)
  end if 
  allocate(scounts_c(numDomain_c), stat=stat)
  if (stat /=0) then
    write(*,*) "Allocation failed: scounts_c"
    call exit(1)
  end if 

  offset = 0
  do i = 1, numDomain_r
    displs_r(i) = offset
    if (i-1 < residueMol_r) then
      scounts_r(i) = numMolPerDomain_r + 1
    else
      scounts_r(i) = numMolPerDomain_r
    end if
    offset = offset + scounts_r(i)
  end do

  offset = 0
  do i = 1, numDomain_c
    displs_c(i) = offset
    if (i-1 < residueMol_c) then
      scounts_c(i) = numMolPerDomain_c + 1
    else
      scounts_c(i) = numMolPerDomain_c
    end if
    offset = offset + scounts_c(i)
  end do

  num_r = scounts_r(r_group_idx + 1)
  num_c = scounts_c(c_group_idx + 1)
  r_start = displs_r(r_group_idx + 1) + 1
  r_end = r_start + num_r - 1
  c_start = displs_c(c_group_idx + 1) + 1
  c_end = c_start + num_c - 1

  displs_r = displs_r * 3 * numFrame
  displs_c = displs_c * 3 * numFrame
  scounts_r = scounts_r * 3 * numFrame
  scounts_c = scounts_c * 3 * numFrame

  !check if myrank is at the ending boundary and if indexes are coincident
  if (r_group_idx == numDomain_r - 1) then
    if (r_end /= totNumMol) then
      write(*,*) "Error: r_end /= totNumMol, r_end =", r_end
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if
  end if
  if (c_group_idx == numDomain_c - 1) then
    if (c_end /= totNumMol) then
      write(*,*) "Error: c_end /= totNumMol"
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if
  end if
  if (myrank == root) then
    write(*,*) "numDomain_r x numDomain_c = ", numDomain_r, " x ", numDomain_c 
  end if
!  write(*,*) "my rank =", myrank
!  write(*,*) "r_start, r_end =", r_start, r_end
!  write(*,*) "c_start, c_end =", c_start, c_end
!  write(*,*)

  !prepare memory for all ranks
  allocate(pos_r(3, numFrame, num_r), stat=stat)
  if (stat /=0) then
    write(*,*) "Allocation failed: pos_r"
    call mpi_abort(MPI_COMM_WORLD, 1, ierr);
    call exit(1)
  end if 
  allocate(vel_r(3, numFrame, num_r), stat=stat)
  if (stat /=0) then
    write(*,*) "Allocation failed: vel_r"
    call mpi_abort(MPI_COMM_WORLD, 1, ierr);
    call exit(1)
  end if 
  allocate(pos_c(3, numFrame, num_c), stat=stat)
  if (stat /=0) then
    write(*,*) "Allocation failed: pos_c"
    call mpi_abort(MPI_COMM_WORLD, 1, ierr);
    call exit(1)
  end if 
  allocate(vel_c(3, numFrame, num_c), stat=stat)
  if (stat /=0) then
    write(*,*) "Allocation failed: vel_r"
    call mpi_abort(MPI_COMM_WORLD, 1, ierr);
    call exit(1)
  end if 

  !read trajectory at root
  if (myrank == root) then
    write(*,*) "start reading trajectory..."
    starttime = MPI_Wtime()
    sysNumAtom = get_natom(dataFilename)
    if (is_pm_mode .and. sysNumAtom /= totNumMol) then
      write(*,*) "sysNumAtom = ", sysNumAtom, ", totNumMol = ", totNumMol
      write(*,*) "In COM mode, sysNumAtom should equal to totNumMol!"
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if
    write(*,*) "sysNumAtom=", sysNumAtom

    allocate(pos(3, numFrame, totNumMol), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: pos"
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if 
    allocate(vel(3, numFrame, totNumMol), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: vel"
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if 
    allocate(pos_tmp(3, sysNumAtom), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: pos_tmp"
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if 
    allocate(vel_tmp(3, sysNumAtom), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: vel_tmp"
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if 
    allocate(time(numFrame), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: time"
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if 

    numFrameRead = 0
    call open_trajectory(dataFileHandle, dataFilename)
    do i = 1, numFrame
      call read_trajectory(dataFileHandle, sysNumAtom, is_periodic, pos_tmp, vel_tmp, cell, time(i), stat)
      if (stat /= 0) then
        write(*,*) "Reading trajectory error"
        call mpi_abort(MPI_COMM_WORLD, 1, ierr);
        call exit(1)
      end if 
      numFrameRead = numFrameRead + 1
      if (is_pm_mode) then
        pos(:, i, :) = pos_tmp
        vel(:, i, :) = vel_tmp
      else
        call com_pos(pos(:, i, :), pos_tmp, start_index, sys, cell)
        call com_vel(vel(:, i, :), vel_tmp, start_index, sys)
      end if
      do j = 1, skip-1
        call read_trajectory(dataFileHandle, sysNumAtom, is_periodic, pos_tmp, vel_tmp, cell, tmp_r, stat)
        if (stat > 0) then
          write(*,*) "Reading trajectory error"
          call mpi_abort(MPI_COMM_WORLD, 1, ierr);
          call exit(1)
        else if (stat < 0) then
          !end of file
          exit
        end if 
      end do
    end do
    call close_trajectory(dataFileHandle)
    if (myrank == root) write(*,*) "numFrameRead = ", numFrameRead
    if (numFrameRead /= numFrame) then
      write(*,*) "Number of frames expected to read is not the same as actually read!"
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if

    timestep = time(2) - time(1)
    deallocate(pos_tmp)
    deallocate(vel_tmp)
    deallocate(time)
    endtime = MPI_Wtime()
    write(*,*) "finished reading trajectory. It took ", endtime - starttime, "seconds"
    write(*,*) "timestep = ", timestep
    write(*,*) "cell = ", cell
  else
    !not root, allocate dummy pos to inhibit error messages
    allocate(pos(1, 1, 1), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: dummy pos on rank", myrank
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if
    allocate(vel(1, 1, 1), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: dummy vel on rank", myrank
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if
  end if

  !distribute trajectory data collectively
  if (myrank == root) write(*,*) "start broadcasting trajectory"
  starttime = MPI_Wtime()
  if (r_group_idx == 0) then
    call mpi_scatterv(pos, scounts_c, displs_c, mpi_double_precision, pos_c,&
                      scounts_c(c_group_idx + 1), mpi_double_precision, root, row_comm, ierr)
  end if
  call mpi_bcast(pos_c, scounts_c(c_group_idx + 1), mpi_double_precision, root, col_comm, ierr)

  if (c_group_idx == 0) then
    call mpi_scatterv(pos, scounts_r, displs_r, mpi_double_precision, pos_r,&
                      scounts_r(r_group_idx + 1), mpi_double_precision, root, col_comm, ierr)
  end if
  call mpi_bcast(pos_r, scounts_r(r_group_idx + 1), mpi_double_precision, root, row_comm, ierr)

  if (r_group_idx == 0) then
    call mpi_scatterv(vel, scounts_c, displs_c, mpi_double_precision, vel_c,&
                      scounts_c(c_group_idx + 1), mpi_double_precision, root, row_comm, ierr)
  end if
  call mpi_bcast(vel_c, scounts_c(c_group_idx + 1), mpi_double_precision, root, col_comm, ierr)

  if (c_group_idx == 0) then
    call mpi_scatterv(vel, scounts_r, displs_r, mpi_double_precision, vel_r,&
                      scounts_r(r_group_idx + 1), mpi_double_precision, root, col_comm, ierr)
  end if
  call mpi_bcast(vel_r, scounts_r(r_group_idx + 1), mpi_double_precision, root, row_comm, ierr)

  call mpi_bcast(cell, 3, mpi_double_precision, root, MPI_COMM_WORLD, ierr)
  endtime = MPI_Wtime()
  if (myrank == root) write(*,*) "finished broadcasting trajectory. It took ", endtime - starttime, " seconds"

  deallocate(pos)
  deallocate(vel)

  !decomposition
  if (is_sd) then
    if (myrank == root) write(*,*) "start spatial decomposition"
  else
    if (myrank == root) write(*,*) "start one-two decomposition"
  end if
  starttime = MPI_Wtime()

  allocate(vv(numFrame))
  if (stat /=0) then
    write(*,*) "Allocation failed: vv"
    call mpi_abort(MPI_COMM_WORLD, 1, ierr);
    call exit(1)
  end if 

  allocate(nCorr(maxLag+1, numMolType*(numMolType+1)), stat=stat)
  if (stat /=0) then
    write(*,*) "Allocation failed: nCorr"
    call mpi_abort(MPI_COMM_WORLD, 1, ierr);
    call exit(1)
  end if 
  nCorr = 0d0

  if (is_sd) then
    ! *sqrt(3) to accommodate the longest distance inside a cubic (diagonal)
    num_rBin = ceiling(cell(1) / 2d0 * sqrt(3d0) / rBinWidth)
    if (myrank == root) write(*,*) "num_rBin = ", num_rBin

    allocate(sdCorr(maxLag+1, num_rBin, numMolType*numMolType), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: sdCorr"
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if 
    sdCorr = 0d0

    allocate(rho(num_rBin, numMolType*numMolType), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: rho"
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if 
    rho = 0d0

    allocate(rBinIndex(numFrame), stat=stat)
    if (stat /= 0) then
      write(*,*) "Allocation failed: rBinIndex"
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if 
  end if

  if (myrank == root) write(*,*) "time for allocation (sec):", MPI_Wtime() - starttime
  do j = c_start, c_end
    do i = r_start, r_end
      if (i == j) then
        !TODO: this autocorrelation part should utilize FFT
        if (myrank == root) write(*,*) "loop r =",i-r_start+1, " of ", num_r,&
                                          ", c =", j-c_start+1, " of ", num_c
        starttime2 = MPI_Wtime()
        molTypePairAllIndex = getMolTypeIndex(i, sys%mol(:)%num)
        do k = 1, maxLag+1
          numFrame_k = numFrame - k + 1
          vv(1:numFrame_k) = sum(vel_r(:, k:numFrame, i-r_start+1) * vel_c(:, 1:numFrame_k, j-c_start+1), 1)
          nCorr(k, molTypePairAllIndex) = nCorr(k, molTypePairAllIndex) + sum(vv(1:numFrame_k))
        end do
      else
        if (myrank == root) write(*,*) "loop r =",i-r_start+1, " of ", num_r,&
                                          ", c =", j-c_start+1, " of ", num_c
        starttime2 = MPI_Wtime()
        molTypePairIndex = getMolTypePairIndex(i, j, sys%mol(:)%num)
        molTypePairAllIndex = molTypePairIndex + numMolType
        if (is_sd) then
          call getBinIndex(pos_r(:,:,i-r_start+1), pos_c(:,:,j-c_start+1), cell(1), rBinWidth, rBinIndex)
        end if
        do k = 1, maxLag+1
          numFrame_k = numFrame - k + 1
          vv(1:numFrame_k) = sum(vel_r(:, k:numFrame, i-r_start+1) * vel_c(:, 1:numFrame_k, j-c_start+1), 1)
          !TODO: test if this sum should be put here or inside the following loop for better performance
          nCorr(k, molTypePairAllIndex) = nCorr(k, molTypePairAllIndex) + sum(vv(1:numFrame_k))
          if (is_sd) then
            do n = 1, numFrame_k
              tmp_i = rBinIndex(n)
              if (tmp_i <= num_rBin) then
                sdCorr(k, tmp_i, molTypePairIndex) = sdCorr(k, tmp_i, molTypePairIndex) + vv(n)
              end if
              !TODO: need test
              !nCorr(k, molTypePairIndex) = corr(k, molTypePairIndex) + vv(n)
            end do
          end if
        end do
        if (is_sd) then
          do t = 1, numFrame
            tmp_i = rBinIndex(t)
            if (tmp_i <= num_rBin) then
              rho(tmp_i, molTypePairIndex) = rho(tmp_i, molTypePairIndex) + 1d0
            end if
          end do
        end if
      end if
      if (myrank == root) write(*,*) "time for this loop (sec):", MPI_Wtime() - starttime2
      if (myrank == root) write(*,*) 
    end do
  end do
  if (is_sd) then
    deallocate(rBinIndex)
  end if
  endtime = MPI_Wtime()
  if (myrank == root) write(*,*) "finished decomposition. It took ", endtime - starttime, " seconds"

  !collect nCorr, sdCorr and rho
  if (myrank == root) write(*,*) "start collecting results"
  starttime = MPI_Wtime()
  if (myrank == root) then
    call mpi_reduce(MPI_IN_PLACE, nCorr, size(nCorr), mpi_double_precision, MPI_SUM, root, MPI_COMM_WORLD, ierr)
    if (is_sd) then
      call mpi_reduce(MPI_IN_PLACE, sdCorr, size(sdCorr), mpi_double_precision, MPI_SUM, root, MPI_COMM_WORLD, ierr)
      call mpi_reduce(MPI_IN_PLACE, rho, size(rho), mpi_double_precision, MPI_SUM, root, MPI_COMM_WORLD, ierr)
    end if
  else
    call mpi_reduce(nCorr, dummy_null, size(nCorr), mpi_double_precision, MPI_SUM, root, MPI_COMM_WORLD, ierr)
    if (is_sd) then
      call mpi_reduce(sdCorr, dummy_null, size(sdCorr), mpi_double_precision, MPI_SUM, root, MPI_COMM_WORLD, ierr)
      call mpi_reduce(rho, dummy_null, size(rho), mpi_double_precision, MPI_SUM, root, MPI_COMM_WORLD, ierr)
    end if
  end if
  endtime = MPI_Wtime()
  if (myrank == root) write(*,*) "finished collecting results. It took ", endtime - starttime, " seconds"

  !normalization at root and then output
  if (myrank == root) then
    allocate(norm(maxLag+1), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: norm"
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if 

    norm = [ (numFrame - (i-1), i = 1, maxLag+1) ] * 3d0
    do n = 1, numMolType*(numMolType+1)
      nCorr(:,n) = nCorr(:,n) / norm
    end do

    if (is_sd) then
      rho = rho / numFrame
      do n = 1, numMolType*numMolType
        do i = 1, num_rBin
          sdCorr(:,i,n) = sdCorr(:,i,n) / norm / rho(i, n)
        end do
      end do
    end if

    deallocate(norm)

    !output results
    write(*,*) "start writing outputs"
    starttime = MPI_Wtime()
    call output()
    endtime = MPI_Wtime()
    write(*,*) "finished writing outputs. It took ", endtime - starttime, " seconds"
  end if

  if (myrank == root) write(*,*)
  if (myrank == root) write(*,*) "time for the whole program (sec):", MPI_Wtime() - prog_starttime
  call mpi_finalize(ierr)
  stop

contains
  subroutine getBinIndex(p1, p2, cell, rBinWidth, rBinIndex)
    implicit none
    real(8), intent(in) :: p1(:,:), p2(:,:), cell(3), rBinWidth
    !p1(dim,timeFrame)
    integer, intent(out) :: rBinIndex(:)
    real(8) :: pp(size(p1,1), size(p1,2))
    integer :: d
    
    pp = p1 - p2
    do d = 1, 3
      pp(d, :) = pp(d, :) - nint(pp(d, :) / cell(d)) * cell(d)
    end do
    rBinIndex = ceiling(sqrt(sum(pp*pp, 1)) / rBinWidth)
    where (rBinIndex == 0)
      rBinIndex = 1
    end where
!    where (rBinIndex >= ceiling(cellLength / 2.d0 / rBinWidth))
!    where (rBinIndex > num_rBin)
!      rBinIndex = -1
!    end where
  end subroutine getBinIndex

  integer function getMolTypeIndex(i, numMol)
    implicit none
    integer, intent(in) :: i, numMol(:)
    integer :: n, numMol_acc
!    integer, save :: numMolType = size(numMol)

    getMolTypeIndex = -1
    numMol_acc = 0
    do n = 1, numMolType
      numMol_acc = numMol_acc + numMol(n)
      if (i <= numMol_acc) then
        getMolTypeIndex = n
        return
      end if
    end do
  end function getMolTypeIndex
  
  integer function getMolTypePairIndex(i, j, numMol)
    implicit none
    integer, intent(in) :: i, j, numMol(:)
    integer :: ii, jj
!    integer, save :: numMolType = size(numMol)
  
    ii = getMolTypeIndex(i, numMol)
    jj = getMolTypeIndex(j, numMol)
    getMolTypePairIndex = (ii-1)*numMolType + jj
  end function getMolTypePairIndex

  subroutine com_pos(com_p, pos, start_index, sys, cell)
    implicit none
    real(8), dimension(:, :), intent(out) :: com_p
    real(8), dimension(:, :), intent(in) :: pos 
    real(8), dimension(:, :), allocatable :: pos_gathered
    integer, dimension(:), intent(in) :: start_index
    type(system), intent(in) :: sys
    real(8), dimension(3), intent(in) :: cell
    integer :: d, i, j, k, idx_begin, idx_end, idx_com, num_atom

    idx_com = 0
    do i = 1, size(sys%mol)
      num_atom = size(sys%mol(i)%atom)
      allocate(pos_gathered(3, num_atom), stat=stat)
      if (stat /=0) then
        write(*,*) "Allocation failed: pos_gathered"
        call mpi_abort(MPI_COMM_WORLD, 1, ierr);
        call exit(1)
      end if
      do j = 1, sys%mol(i)%num
        idx_begin = start_index(i) + (j-1) * num_atom
        idx_end = idx_begin + num_atom - 1
        idx_com = idx_com + 1
        call gatherMolPos(pos_gathered, pos(:, idx_begin:idx_end), cell)
        do d = 1, 3
          com_p(d, idx_com) = sum(pos_gathered(d, :) * sys%mol(i)%atom(:)%mass) / sum(sys%mol(i)%atom(:)%mass)
        end do
      end do
      deallocate(pos_gathered)
    end do
  end subroutine com_pos

  subroutine gatherMolPos(pos_gathered, pos, cell)
    implicit none
    real(8), dimension(:, :), intent(out) :: pos_gathered
    real(8), dimension(:, :), intent(in) :: pos
    real(8), dimension(3), intent(in) :: cell
    real(8), dimension(3) :: ref_pos
    integer :: d

    ref_pos = pos(:, 1)
    do d = 1, 3
      pos_gathered(d, :) = pos(d, :) - ref_pos(d)
      pos_gathered(d, :) = ref_pos(d) + pos_gathered(d, :) - &
                           nint(pos_gathered(d, :) / cell(d)) * cell(d)
    end do
  end subroutine gatherMolPos

  subroutine com_vel(com_v, vel, start_index, sys)
    implicit none
    real(8), dimension(:, :), intent(out) :: com_v
    real(8), dimension(:, :), intent(in) :: vel 
    integer, dimension(:), intent(in) :: start_index
    type(system), intent(in) :: sys
    integer :: d, i, j, k, idx_begin, idx_end, idx_com

    com_v = 0d0
    idx_com = 0
    do i = 1, size(sys%mol)
      do j = 1, sys%mol(i)%num
        idx_begin = start_index(i) + (j-1) * size(sys%mol(i)%atom)
        idx_end = idx_begin + size(sys%mol(i)%atom) - 1
        idx_com = idx_com + 1
        do d = 1, 3
          com_v(d, idx_com) = com_v(d, idx_com) + &
              sum(vel(d, idx_begin:idx_end) * sys%mol(i)%atom(:)%mass) / sum(sys%mol(i)%atom(:)%mass)
        end do
      end do
    end do
  end subroutine com_vel

  subroutine output()
    use H5DS
    use H5LT
    use HDF5
    implicit none
    real(8), allocatable :: timeLags(:), rBins(:)
    integer :: ierr
    integer(hid_t) :: fid, did1, did2, did3, sid1, sid2

    allocate(timeLags(maxLag+1), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: timeLags"
      call mpi_abort(MPI_COMM_WORLD, 1, ierr);
      call exit(1)
    end if 
    timeLags = [ (dble(i), i = 0, maxLag) ] * timestep
    
    if (is_sd) then
      allocate(rBins(num_rBin), stat=stat)
      if (stat /=0) then
        write(*,*) "Allocation failed: rBins"
        call mpi_abort(MPI_COMM_WORLD, 1, ierr);
        call exit(1)
      end if 
      rBins = [ (i - 0.5d0, i = 1, num_rBin) ] * rBinWidth
    end if

    call H5open_f(ierr)

    ! create a HDF5 file
    call H5Fcreate_f(outFilename, H5F_ACC_TRUNC_F, fid, ierr)

    ! create and write dataset
    call H5LTset_attribute_double_f(fid, "/", "timestep", [timestep], int(1, kind=size_t), ierr)
    call H5LTset_attribute_int_f(fid, "/", "charge", charge, size(charge, kind=size_t), ierr)
    call H5LTset_attribute_int_f(fid, "/", "numMol", sys%mol(:)%num, size(sys%mol(:)%num, kind=size_t), ierr)
    call H5LTset_attribute_double_f(fid, "/", "cell", cell, size(cell, kind=size_t), ierr)

    call H5LTmake_dataset_double_f(fid, "nCorr", 2, &
        [size(nCorr, 1, kind=hsize_t), size(nCorr, 2, kind=hsize_t)], nCorr, ierr)
    call H5Dopen_f(fid, "nCorr", did1, ierr)

    if (is_sd) then
      call H5LTmake_dataset_double_f(fid, "sdCorr", 3, &
          [size(sdCorr, 1, kind=hsize_t), size(sdCorr, 2, kind=hsize_t), size(sdCorr, 3, kind=hsize_t)], sdCorr, ierr)
      call H5Dopen_f(fid, "sdCorr", did2, ierr)

      call H5LTmake_dataset_double_f(fid, "rho", 2, &
          [size(rho, 1, kind=hsize_t), size(rho, 2, kind=hsize_t)], rho, ierr)
      call H5Dopen_f(fid, "rho", did3, ierr)
    end if

    call H5LTmake_dataset_double_f(fid, "timeLags", 1, [size(timeLags, kind=hsize_t)], timeLags, ierr)
    call H5Dopen_f(fid, "timeLags", sid1, ierr)

    if (is_sd) then
      call H5LTmake_dataset_double_f(fid, "rBins", 1, [size(rBins, kind=hsize_t)], rBins, ierr)
      call H5Dopen_f(fid, "rBins", sid2, ierr)
    end if

    ! attach scale dimension
    call H5DSattach_scale_f(did1, sid1, 1, ierr)
    if (is_sd) then
      call H5DSattach_scale_f(did2, sid1, 1, ierr)
      call H5DSattach_scale_f(did2, sid2, 2, ierr)
      call H5DSattach_scale_f(did3, sid2, 1, ierr)
    end if

    call H5Dclose_f(sid1, ierr)
    call H5Dclose_f(did1, ierr)
    if (is_sd) then
      call H5Dclose_f(sid2, ierr)
      call H5Dclose_f(did2, ierr)
      call H5Dclose_f(did3, ierr)
    end if
    call H5Fclose_f(fid, ierr)
    call H5close_f(ierr)
  end subroutine output

  integer function count_arg(i, num_arg)
    implicit none
    integer, intent(in) :: i, num_arg
    character(len=128) :: arg
    integer :: j, stat
    logical :: is_numeric
    !count number of arguments for the (i-1)-th option
    count_arg = 0
    j = i
    do while (.true.)
      if (j > num_arg) then
        return
      end if
      call get_command_argument(number=j, value=arg, status=stat)
      if (stat /= 0) then
        if (myrank == root) then
          call mpi_abort(MPI_COMM_WORLD, 1, ierr);
          write(*,*) "Error: unable to count the number of arguments for the ", i-1, "-th option"
          call print_usage()
          call exit(1)
        end if
      else if (arg(1:1) == '-' ) then
        is_numeric = verify(arg(2:2), '0123456789') .eq. 0 
        if (.not. is_numeric) return !end of data file arguments
      end if
      j = j + 1
      count_arg = count_arg + 1
    end do
  end function count_arg

  subroutine print_usage()
    implicit none
    write(*, *) "usage: $ decompose_mpi <infile.trr> <numFrameToRead> <-pa | -pm ...> [options]"
    write(*, *) "options: "
    write(*, *) "  -pa <topfile.top> <molecule1> <start_index1> [<molecule2> <start_index2>...]:"
    write(*, *) "   read parameters from topology file. ignored when -pm is given"
    write(*, *) 
    write(*, *) "  -pm <molecule1> <charge1> <number1> [<molecule2> <charge2> <number2>...]:"
    write(*, *) "   manually assign parameters for single-atom-molecule system"
    write(*, *) 
    write(*, *) "  -o <outfile>: output filename. default = corr.h5"
    write(*, *) 
    write(*, *) "  -s <skip>: skip=1 means no frames are skipped, which is default."
    write(*, *) "             skip=2 means reading every 2nd frame."
    write(*, *) 
    write(*, *) "  -l <maxlag>: maximum time lag. default = <numFrameToRead - 1>"
    write(*, *) 
    write(*, *) "  -nosd: no spatial decomposition, do only one-two decomposition"
    write(*, *) 
    write(*, *) "  -r <rbinwidth(nm)>:"
    write(*, *) "   spatial decomposition r-bin width. default = 0.01, ignored when -nosd is given"
    write(*, *) 
    write(*, *) "  -d <numDomain_r> <numDomain_c>:" 
    write(*, *) "   manually assign the MPI decomposition pattern"
  end subroutine print_usage

end program decompose_mpi
