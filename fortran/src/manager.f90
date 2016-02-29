module manager
  use mpiproc
  use hdf5
  use utility, only: handle, get_pairindex_upper_diag
  use varpars, only: line_len, line_len_str, dp, decond_version, &
                     trjfile, corrfile, dec_mode, &
                     dec_mode_ec0, dec_mode_ec1, dec_mode_vsc, &
                     temperature, numframe, nummoltype, &
                     sys, charge, totnummol, num_moltypepair_all, &
                     maxlag, skiptrj, is_sd, is_ed, sysnumatom, cell, &
                     timestep
  use top, only: open_top, close_top, read_top, print_sys
  use xdr, only: open_trajectory, close_trajectory, read_trajectory, get_natom
  use correlation, only: corr
  use spatial_dec, only: sd_init, rbinwidth, pos, sd_binIndex, num_rbin, &
                         sdcorr, sdpaircount, sd_prep, sd_broadcastpos, &
                         com_pos, sd_prep_corrmemory, sd_collectcorr, &
                         sd_average, sd_getbinindex, sd_cal_num_rbin, &
                         sd_make_rbins, sd_finish
  use energy_dec, only: ed_init, skipeng, num_engfiles, engfiles, ebinwidth, &
                        ed_binIndex, edcorr, num_ebin, edpaircount, ed_prep, &
                        ed_prep_corrmemory, ed_collectcorr, ed_average, &
                        ed_getbinindex, ed_make_ebins, ed_finish

  implicit none
  private
  public init_config, read_config, prepare, decompose, output, finish

  integer :: num_arg, num_subarg, num_arg_per_moltype
  character(len=line_len) :: arg
  integer, allocatable :: start_index(:)
  type(handle) :: topfileio
  character(len=line_len) :: logfile, topfile
  integer(hid_t) :: corrfileio
  integer :: i, j, k, n, t, stat, numframe_k, numframe_read, tmp_i
  integer :: moltypepair_idx, moltypepair_allidx
  real(dp) :: tmp_r
  type(handle) :: trjfileio
  integer, allocatable :: framecount(:)
  real(dp), allocatable :: pos_tmp(:, :), vel_tmp(:, :), vv(:)
  !one frame data (dim=3, atom)
  real(dp), allocatable :: vel(:, :, :)
  !pos(dim=3, timeFrame, atom), vel(dim=3, timeFrame, atom)
  real(dp), allocatable :: time(:), ncorr(:, :), corr_tmp(:)
  !MPI variables
  real(dp), allocatable :: vel_r(:, :, :), vel_c(:, :, :)

contains
  subroutine init_config()
    num_arg = command_argument_count()

    ! necessary arguments
    dec_mode = 'undefined'
    temperature = -1.0
    numframe = -1

    corrfile = 'corr.c5'
    skiptrj = 1
    maxlag = -1
    is_sd = .false.
    is_ed = .false.
    num_domain_r = 0
    num_domain_c = 0
    call sd_init()
    call ed_init()
  end subroutine init_config

  subroutine read_config()
    !read parameters for all ranks
    i = 1
    do while (i <= num_arg)
      call get_command_argument(number=i, value=arg, status=stat)
      i = i + 1
      select case (arg)
      case ('-' // dec_mode_ec0)
        if (myrank == root .and. dec_mode /= 'undefined') then
          write(*,*) "Only one mode can be given!"
          call print_usage()
          call mpi_abend()
        end if
        dec_mode = dec_mode_ec0
        call get_command_argument(i, trjfile)
        i = i + 1
        call get_command_argument(i, topfile)
        i = i + 1
        num_subarg = count_arg(i, num_arg)
        num_arg_per_moltype = 2
        if (mod(num_subarg, num_arg_per_moltype) > 0 .or. num_subarg < num_arg_per_moltype) then
          if (myrank == root) then
            write(*,*) "Wrong number of arguments for -" // trim(dec_mode) // ': ', num_subarg + 2
            call print_usage()
            call mpi_abend()
          end if
        end if

        nummoltype = num_subarg / num_arg_per_moltype

        allocate(sys%mol(nummoltype), stat=stat)
        if (stat /=0) then
          write(*,*) "Allocation failed: sys%mol"
          call mpi_abend()
        end if

        allocate(charge(nummoltype), stat=stat)
        if (stat /=0) then
          write(*,*) "Allocation failed: charge"
          call mpi_abend()
        end if

        allocate(start_index(nummoltype), stat=stat)
        if (stat /=0) then
          write(*,*) "Allocation failed: start_index"
          call exit(1)
        end if

        do n = 1, nummoltype
          call get_command_argument(i, sys%mol(n)%type)
          i = i + 1
          call get_command_argument(i, arg)
          read(arg, *) start_index(n)
          i = i + 1
        end do

        if (myrank == root) then
          write(*, "(A)") "sys%mol%type = "
          do n = 1, nummoltype
            write(*, "(A, X)", advance='no') trim(sys%mol(n)%type)
          end do
          write(*,*)
          write(*,*) "start_index = ", start_index
        end if

        !read topFile
        topfileio = open_top(topfile)
        call read_top(topfileio, sys)
        call close_top(topfileio)
        if (myrank == root) call print_sys(sys)

        do n = 1, nummoltype
          charge(n) = nint(sum(sys%mol(n)%atom(:)%charge))
        end do
        totnummol = sum(sys%mol(:)%num)
        if (myrank == root) write(*,*) "charge = ", charge

      case ('-' // dec_mode_ec1)
        if (myrank == root .and. dec_mode /= 'undefined') then
          write(*,*) "Only one mode can be given!"
          call print_usage()
          call mpi_abend()
        end if
        dec_mode = dec_mode_ec1
        call get_command_argument(i, trjfile)
        i = i + 1
        num_subarg = count_arg(i, num_arg)
        num_arg_per_moltype = 3
        if (mod(num_subarg, num_arg_per_moltype) > 0 .or. num_subarg < num_arg_per_moltype) then
          if (myrank == root) then
            write(*,*) "Wrong number of arguments for -" // trim(dec_mode) // ': ', num_subarg + 1
            call print_usage()
            call mpi_abend()
          end if
        end if

        nummoltype = num_subarg / num_arg_per_moltype

        allocate(sys%mol(nummoltype), stat=stat)
        if (stat /=0) then
          write(*,*) "Allocation failed: sys%mol"
          call mpi_abend()
        end if

        allocate(charge(nummoltype), stat=stat)
        if (stat /=0) then
          write(*,*) "Allocation failed: charge"
          call mpi_abend()
        end if

        do n = 1, nummoltype
          call get_command_argument(i, sys%mol(n)%type)
          i = i + 1
          call get_command_argument(i, arg)
          i = i + 1
          read(arg, *) charge(n)
          call get_command_argument(i, arg)
          i = i + 1
          read(arg, *) sys%mol(n)%num
        end do

        totnummol = sum(sys%mol(:)%num)
        if (myrank == root) then
          write(*, "(A)") "sys%mol%type = "
          do n = 1, nummoltype
            write(*, "(A, X)", advance='no') trim(sys%mol(n)%type)
          end do
          write(*,*)
          write(*,*) "charge = ", charge
          write(*,*) "sys%mol%num = ", sys%mol%num
        end if

      case ('-vsc')
        if (myrank == root .and. dec_mode /= 'undefined') then
          write(*,*) "Only one mode can be given!"
          call print_usage()
          call mpi_abend()
        end if
        dec_mode = dec_mode_vsc
        call get_command_argument(i, trjfile)
        i = i + 1
        num_subarg = count_arg(i, num_arg)
        num_arg_per_moltype = 2
        if (mod(num_subarg, num_arg_per_moltype) > 0 .or. num_subarg < num_arg_per_moltype) then
          if (myrank == root) then
            write(*,*) "Wrong number of arguments for -" // trim(dec_mode) // ': ', num_subarg + 1
            call print_usage()
            call mpi_abend()
          end if
        end if

        nummoltype = num_subarg / num_arg_per_moltype

        allocate(sys%mol(nummoltype), stat=stat)
        if (stat /=0) then
          write(*,*) "Allocation failed: sys%mol"
          call mpi_abend()
        end if

        do n = 1, nummoltype
          call get_command_argument(i, sys%mol(n)%type)
          i = i + 1
          call get_command_argument(i, arg)
          i = i + 1
          read(arg, *) sys%mol(n)%num
        end do

        totnummol = sum(sys%mol(:)%num)
        if (myrank == root) then
          write(*, "(A)") "sys%mol%type = "
          do n = 1, nummoltype
            write(*, "(A, X)", advance='no') trim(sys%mol(n)%type)
          end do
          write(*,*)
          write(*,*) "sys%mol%num = ", sys%mol%num
        end if

        ! unused for viscosity
        allocate(charge(nummoltype), stat=stat)
        if (stat /=0) then
          write(*,*) "Allocation failed: charge"
          call mpi_abend()
        end if
        charge = 0

      case ('-n', '--numframe')
        call get_command_argument(i, arg)
        i = i + 1
        read(arg, *) numframe  ! in the unit of frame number

      case ('-T', '--temperature')
        call get_command_argument(i, arg)
        i = i + 1
        if (trim(arg(scan(arg, '.', .true.) + 1:)) == 'log') then
          logfile = arg
          temperature = getTfromLog(logfile)
        else
          read(arg, *, iostat=stat) temperature
          if (stat > 0) then
            write(*,*) "Error reading temperature: ", trim(arg)
            call mpi_abend()
          end if
        end if

      case ('-o')
        call get_command_argument(i, corrfile)
        i = i + 1

      case ('-skiptrj')
        call get_command_argument(i, arg)
        i = i + 1
        read(arg, *) skiptrj

      case ('-skipeng')
        call get_command_argument(i, arg)
        i = i + 1
        read(arg, *) skipeng

      case ('-l')
        call get_command_argument(i, arg)
        i = i + 1
        read(arg, *) maxlag  ! in the unit of frame number

      case ('-sd')
        is_sd = .true.

      case ('-ed')
        is_ed = .true.
        num_engfiles = count_arg(i, num_arg)
        do n = 1, num_engfiles
          call get_command_argument(i, engfiles(n))
          i = i + 1
        end do

      case ('-sbwidth')
        call get_command_argument(i, arg)
        i = i + 1
        read(arg, *) rbinwidth

      case ('-ebwidth')
        call get_command_argument(i, arg)
        i = i + 1
        read(arg, *) ebinwidth

      case ('-d')
        num_subarg = 2
        call get_command_argument(i, arg)
        i = i + 1
        read(arg, *) num_domain_r

        call get_command_argument(i, arg)
        i = i + 1
        read(arg, *) num_domain_c

      case ('-h', '--help')
        if (myrank == root) call print_usage()
        call mpi_abend()

      case ('-v', '--version')
        if (myrank == root) write(*,*) "Decond " // decond_version
        call mpi_abend()

      case default
        if (myrank == root) write(*,*) "Unknown argument: ", trim(adjustl(arg))
        if (myrank == root) call print_usage()
        call mpi_abend()
      end select
    end do

    !auto1, auto2, ...autoN, cross11, cross12, ..., cross1N, cross22, ...cross2N, cross33,..., crossNN
    != [auto part] + [cross part]
    != [nummoltype] + [nummoltype * (nummoltype + 1) / 2]
    num_moltypepair_all = nummoltype * (nummoltype + 3) / 2

    if (maxlag == -1) then
      maxlag = numframe - 1
    end if

    if (dec_mode == 'undefined') then
      if (myrank == root) then
        write(*,*) "A mode must be given!"
        call print_usage()
        call mpi_abend()
      end if
    end if

    if (temperature == -1) then
      if (myrank == root) then
        write(*,*) "temperature must be given!"
        call print_usage()
        call mpi_abend()
      end if
    end if

    if (numframe == -1) then
      if (myrank == root) then
        write(*,*) "numframe must be given!"
        call print_usage()
        call mpi_abend()
      end if
    end if

    !rank root output parameters read
    if (myrank == root) then
      write(*,*) "outFile = ", trim(corrfile)
      write(*,*) "inFile.trr = ", trim(trjfile)
      write(*,*) "logFile = ", trim(logfile)
      write(*,*) "temperature = ", temperature
      if (dec_mode == dec_mode_ec0) write(*,*) "topFile.top = ", trim(topfile)
      write(*,*) "numframe= ", numframe
      write(*,*) "maxlag = ", maxlag
      if (is_sd) write(*,*) "rbinwidth = ", rbinwidth
      if (is_ed) write(*,*) "ebinwidth = ", ebinwidth
      write(*,*) "nummoltype = ", nummoltype
      write(*,*) "num_domain_r = ", num_domain_r
      write(*,*) "num_domain_c = ", num_domain_c
    end if
  end subroutine read_config

  subroutine prepare()
    if (myrank == root) then
      ! create an HDF5 file
      call h5open_f(ierr)
      call h5fcreate_f(corrfile, h5f_acc_excl_f, corrfileio, ierr)
      if (ierr /= 0) then
        write(*,*) "Failed to create HDF5 file: ", trim(adjustl(corrfile))
        write(*,*) "Probably the file already exists?"
        call mpi_abend()
      end if
    end if

    call domain_dec(totnummol, numframe) ! determine r_start, c_start ...etc.

    if (is_ed) then
      call ed_prep()
    end if

    if (is_sd) then
      call sd_prep()
    end if

    !prepare memory for all ranks
    allocate(vel_r(3, numframe, num_r), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: vel_r"
      call mpi_abend()
    end if
    allocate(vel_c(3, numframe, num_c), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: vel_r"
      call mpi_abend()
    end if

    !read trajectory at root
    if (myrank == root) then
      write(*,*) "start reading trajectory..."
      starttime = mpi_wtime()
      sysnumatom = get_natom(trjfile)
      if (dec_mode == dec_mode_ec1 .and. sysnumatom /= totnummol) then
        write(*,*) "sysnumatom = ", sysnumatom, ", totnummol = ", totnummol
        write(*,*) "In ec1 mode, sysnumatom should equal to totnummol!"
        call mpi_abend()
      end if
      write(*,*) "sysnumatom=", sysnumatom

      allocate(vel(3, numframe, totnummol), stat=stat)
      if (stat /=0) then
        write(*,*) "Allocation failed: vel"
        call mpi_abend()
      end if
      allocate(pos_tmp(3, sysnumatom), stat=stat)
      if (stat /=0) then
        write(*,*) "Allocation failed: pos_tmp"
        call mpi_abend()
      end if
      allocate(vel_tmp(3, sysnumatom), stat=stat)
      if (stat /=0) then
        write(*,*) "Allocation failed: vel_tmp"
        call mpi_abend()
      end if
      allocate(time(numframe), stat=stat)
      if (stat /=0) then
        write(*,*) "Allocation failed: time"
        call mpi_abend()
      end if

      numframe_read = 0
      call open_trajectory(trjfileio, trjfile)
      do i = 1, numframe
        do j = 1, skiptrj-1
          call read_trajectory(trjfileio, sysnumatom, pos_tmp, vel_tmp, cell, tmp_r, stat)
          if (stat > 0) then
            write(*,*) "Reading trajectory error"
            call mpi_abend()
          else if (stat < 0) then
            !end of file
            exit
          end if
        end do
        call read_trajectory(trjfileio, sysnumatom, pos_tmp, vel_tmp, cell, time(i), stat)
        if (stat /= 0) then
          write(*,*) "Reading trajectory error"
          call mpi_abend()
        end if
        numframe_read = numframe_read + 1
        if (dec_mode == dec_mode_ec1) then
          vel(:, i, :) = vel_tmp
          if (is_sd) then
            pos(:, i, :) = pos_tmp
          end if
        else
          call com_vel(vel(:, i, :), vel_tmp, start_index)
          if (is_sd) then
            call com_pos(pos(:, i, :), pos_tmp, start_index, sys, cell)
          end if
        end if
      end do
      call close_trajectory(trjfileio)
      if (myrank == root) write(*,*) "numframe_read = ", numframe_read
      if (numframe_read /= numframe) then
        write(*,*) "Number of frames expected to read is not the same as actually read!"
        call mpi_abend()
      end if

      timestep = time(2) - time(1)
      deallocate(pos_tmp)
      deallocate(vel_tmp)
      deallocate(time)
      endtime = mpi_wtime()
      write(*,*) "finished reading trajectory. It took ", endtime - starttime, "seconds"
      write(*,*) "timestep = ", timestep
      write(*,*) "cell = ", cell
    else
      !not root, allocate dummy vel to inhibit error messages
      allocate(vel(1, 1, 1), stat=stat)
      if (stat /=0) then
        write(*,*) "Allocation failed: dummy vel on rank", myrank
        call mpi_abend()
      end if
    end if

    !distribute trajectory data collectively
    if (myrank == root) write(*,*) "start broadcasting trajectory"
    starttime = mpi_wtime()
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

    deallocate(vel)

    call mpi_bcast(cell, 3, mpi_double_precision, root, mpi_comm_world, ierr)

    if (is_sd) call sd_broadcastpos()
    endtime = mpi_wtime()
    if (myrank == root) write(*,*) "finished broadcasting trajectory. It took ", endtime - starttime, " seconds"
  end subroutine prepare

  subroutine decompose()
    !decomposition
    if (myrank == root) then
      write(*,*) "start one-two decomposition"
      if (is_sd) write(*,*) "start spatial decomposition"
      if (is_ed) write(*,*) "start energy decomposition"
    end if
    starttime = mpi_wtime()

    allocate(vv(numframe))
    if (stat /=0) then
      write(*,*) "Allocation failed: vv"
      call mpi_abend()
    end if

    allocate(ncorr(maxlag+1, num_moltypepair_all), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: ncorr"
      call mpi_abend()
    end if
    ncorr = 0d0

    if (is_sd .or. is_ed) then
      if (is_sd) then
        call sd_cal_num_rbin(cell)
        call sd_prep_corrmemory(maxlag, nummoltype, numframe)
      end if
      if (is_ed) call ed_prep_corrmemory(maxlag, nummoltype, numframe)
    else
      allocate(corr_tmp(2*maxlag+1), stat=stat)
      if (stat /=0) then
        write(*,*) "Allocation failed: corr_tmp"
        call exit(1)
      end if
      corr_tmp = 0d0
    end if

    if (myrank == root) write(*,*) "time for allocation (sec):", mpi_wtime() - starttime

    do j = c_start, c_end
      do i = r_start, r_end
        if (i == j) then
          if (myrank == root) write(*,*) "loop r =",i-r_start+1, " of ", num_r,&
                                            ", c =", j-c_start+1, " of ", num_c
          starttime2 = mpi_wtime()
          moltypepair_allidx = getMolTypeIndex(i, sys%mol(:)%num, nummoltype)
          if (is_sd .or. is_ed) then
            do k = 1, maxlag+1
              numframe_k = numframe - k + 1
              vv(1:numframe_k) = sum(vel_r(:, k:numframe, i-r_start+1) * vel_c(:, 1:numframe_k, j-c_start+1), 1)
              ncorr(k, moltypepair_allidx) = ncorr(k, moltypepair_allidx) + sum(vv(1:numframe_k))
            end do
          else
            do k = 1, 3
              corr_tmp = corr(vel_r(k, :, i-r_start+1), maxlag)
              ncorr(:, moltypepair_allidx) = ncorr(:, moltypepair_allidx) + corr_tmp(maxlag+1:)
            end do
          end if
        else
          if (myrank == root) write(*,*) "loop r =",i-r_start+1, " of ", num_r,&
                                            ", c =", j-c_start+1, " of ", num_c
          starttime2 = mpi_wtime()
          moltypepair_idx = getMolTypePairIndex(i, j, sys%mol(:)%num, nummoltype)
          moltypepair_allidx = moltypepair_idx + nummoltype
          if (is_sd .or. is_ed) then
            if (is_sd) call sd_getbinindex(i-r_start+1, j-c_start+1, cell, sd_binIndex)
            if (is_ed) call ed_getbinindex(i, j, ed_binIndex)
            do k = 1, maxlag+1
              numframe_k = numframe - k + 1
              vv(1:numframe_k) = sum(vel_r(:, k:numframe, i-r_start+1) * vel_c(:, 1:numframe_k, j-c_start+1), 1)
              !TODO: test if this sum should be put here or inside the following loop for better performance
              ncorr(k, moltypepair_allidx) = ncorr(k, moltypepair_allidx) + sum(vv(1:numframe_k))
              do n = 1, numframe_k
                if (is_sd) then
                  tmp_i = sd_binIndex(n)
                  if (tmp_i <= num_rbin) then
                    sdcorr(k, tmp_i, moltypepair_idx) = sdcorr(k, tmp_i, moltypepair_idx) + vv(n)
                  end if
                end if
                if (is_ed) then
                  tmp_i = ed_binIndex(n)
                  if (tmp_i <= num_rbin) then
                    edcorr(k, tmp_i, moltypepair_idx) = edcorr(k, tmp_i, moltypepair_idx) + vv(n)
                  end if
                end if
                !TODO: need test
                !ncorr(k, moltypepair_idx) = corr(k, moltypepair_idx) + vv(n)
              end do
            end do

            do t = 1, numframe
              if (is_sd) then
                tmp_i = sd_binIndex(t)
                if (tmp_i <= num_rbin) then
                  sdpaircount(tmp_i, moltypepair_idx) = sdpaircount(tmp_i, moltypepair_idx) + 1d0
                end if
              end if
              if (is_ed) then
                tmp_i = ed_binIndex(t)
                if (tmp_i <= num_ebin) then
                  edpaircount(tmp_i, moltypepair_idx) = edpaircount(tmp_i, moltypepair_idx) + 1d0
                end if
              end if
            end do

          else ! one-two only
            do k = 1, 3
              corr_tmp = corr(vel_r(k, :, i-r_start+1), vel_c(k, :, j-c_start+1), maxlag)
              ncorr(:, moltypepair_allidx) = ncorr(:, moltypepair_allidx) + corr_tmp(maxlag+1:)
            end do
          end if
        end if
        if (myrank == root) write(*,*) "time for this loop (sec):", mpi_wtime() - starttime2
        if (myrank == root) write(*,*)
      end do
    end do
    if (is_sd) deallocate(sd_binIndex)
    if (is_ed) deallocate(ed_binIndex)

    endtime = mpi_wtime()
    if (myrank == root) write(*,*) "finished decomposition. It took ", endtime - starttime, " seconds"

    !collect ncorr
    if (myrank == root) write(*,*) "start collecting results"
    starttime = mpi_wtime()
    if (myrank == root) then
      write(*,*) "collecting ncorr"
      call mpi_reduce(MPI_IN_PLACE, ncorr, size(ncorr), mpi_double_precision, MPI_SUM, root, mpi_comm_world, ierr)
    else
      call mpi_reduce(ncorr, dummy_null, size(ncorr), mpi_double_precision, MPI_SUM, root, mpi_comm_world, ierr)
    end if
    call mpi_barrier(mpi_comm_world, ierr)
    if (is_sd) call sd_collectcorr()
    if (is_ed) call ed_collectcorr()
    endtime = mpi_wtime()
    if (myrank == root) write(*,*) "finished collecting results. It took ", endtime - starttime, " seconds"

    !average at root
    if (myrank == root) then
      allocate(framecount(maxlag+1), stat=stat)
      if (stat /=0) then
        write(*,*) "Allocation failed: framecount"
        call mpi_abend()
      end if

      do j = 1, nummoltype
        do i = j, nummoltype
          if (i /= j) then
            moltypepair_idx = get_pairindex_upper_diag(i, j, nummoltype)
            moltypepair_allidx = moltypepair_idx + nummoltype
            ncorr(:, moltypepair_allidx) = ncorr(:, moltypepair_allidx) / 2d0
          end if
        end do
      end do

      framecount = [ (numframe - (i-1), i = 1, maxlag+1) ] * 3d0
      do n = 1, num_moltypepair_all
        ncorr(:,n) = ncorr(:,n) / framecount
      end do

      if (is_sd) call sd_average(numframe, nummoltype, framecount)
      if (is_ed) call ed_average(numframe, nummoltype, framecount)

      deallocate(framecount)
    end if
  end subroutine decompose

  subroutine output()
    if (myrank == root) then
      !output results
      write(*,*) "start writing outputs"
      starttime = mpi_wtime()
      call output_corr()
      endtime = mpi_wtime()
      write(*,*) "finished writing outputs. It took ", endtime - starttime, " seconds"
    end if
  end subroutine output

  subroutine output_corr()
    use h5ds
    use h5lt
    use hdf5
    use spatial_dec, only: rbins
    use energy_dec, only: ebins, engMin_global
    implicit none
    real(dp), allocatable :: timeLags(:)
    integer :: ierr
    integer(hid_t) :: dset_ncorr, dset_timeLags, &
                      dset_sdcorr, dset_sdpaircount, dset_rbins, &
                      dset_edcorr, dset_edpaircount, dset_ebins, &
                      grp_sd_id, grp_ed_id, space_id, dset_id

    !HDF5:
    character(len=*), parameter :: GROUP_ROOT = "/", &
                                   GROUP_SPATIAL = "spatialDec", &
                                   GROUP_ENERGY = "energyDec"
    !/Attributes
    character(len=*), parameter :: ATTR_VERSION = "version", &
                                   ATTR_TYPE = "type", &
                                   ATTR_UNIT = "unit", &
                                   OUT_TYPE = "CorrFile"
    !/Dataset
    character(len=*), parameter :: DSETNAME_VOLUME = "volume", &
                                   DSETNAME_TEMP = "temperature", &
                                   DSETNAME_CHARGE = "charge", &
                                   DSETNAME_NUMMOL = "numMol", &
                                   DSETNAME_TIMELAGS = "timeLags", &
                                   DSETNAME_NCORR = "ncorr"

    !/GROUP_SPATIAL or GROUP_ENERGY/Dataset
    character(len=*), parameter :: DSETNAME_DECBINS = "decBins", &
                                   DSETNAME_DECCORR = "decCorr", &
                                   DSETNAME_DECPAIRCOUNT = "decPairCount"


    allocate(timeLags(maxlag+1), stat=stat)
    if (stat /=0) then
      write(*,*) "Allocation failed: timeLags"
      call mpi_abend()
    end if
    timeLags = [ (dble(i), i = 0, maxlag) ] * timestep

    if (is_sd) then
      call sd_make_rbins()
    end if

    if (is_ed) then
      call ed_make_ebins()
    end if

    !create and write attributes
    call H5LTset_attribute_string_f(corrfileio, GROUP_ROOT, ATTR_VERSION, decond_version, ierr)
    call H5LTset_attribute_string_f(corrfileio, GROUP_ROOT, ATTR_TYPE, OUT_TYPE, ierr)

    !create and write datasets
    !volume
    call H5Screate_f(H5S_SCALAR_F, space_id, ierr)
    call H5Dcreate_f(corrfileio, DSETNAME_VOLUME, H5T_NATIVE_DOUBLE, space_id, dset_id, ierr)
    call H5Dwrite_f(dset_id, H5T_NATIVE_DOUBLE, product(cell), [0_hsize_t], ierr)
    call H5Dclose_f(dset_id, ierr)
    call H5Sclose_f(space_id, ierr)
    call H5LTset_attribute_string_f(corrfileio, DSETNAME_VOLUME, ATTR_UNIT, "nm$^3$", ierr)

    !temperature
    call H5Screate_f(H5S_SCALAR_F, space_id, ierr)
    call H5Dcreate_f(corrfileio, DSETNAME_TEMP, H5T_NATIVE_DOUBLE, space_id, dset_id, ierr)
    call H5Dwrite_f(dset_id, H5T_NATIVE_DOUBLE, temperature, [0_hsize_t], ierr)
    call H5Dclose_f(dset_id, ierr)
    call H5Sclose_f(space_id, ierr)
    call H5LTset_attribute_string_f(corrfileio, DSETNAME_TEMP, ATTR_UNIT, "K", ierr)

    !charge
    call H5LTmake_dataset_int_f(corrfileio, DSETNAME_CHARGE, 1, [size(charge, kind=hsize_t)], charge, ierr)
    call H5LTset_attribute_string_f(corrfileio, DSETNAME_CHARGE, ATTR_UNIT, "e", ierr)

    !numMol
    call H5LTmake_dataset_int_f(corrfileio, DSETNAME_NUMMOL, 1, &
                                   [size(sys%mol(:)%num, kind=size_t)], sys%mol(:)%num, ierr)

    !timeLags
    call H5LTmake_dataset_double_f(corrfileio, DSETNAME_TIMELAGS, 1, [size(timeLags, kind=hsize_t)], timeLags, ierr)
    call H5Dopen_f(corrfileio, DSETNAME_TIMELAGS, dset_timeLags, ierr)
    call H5LTset_attribute_string_f(corrfileio, DSETNAME_TIMELAGS, ATTR_UNIT, "ps", ierr)

    !ncorr
    call H5LTmake_dataset_double_f(corrfileio, DSETNAME_NCORR, 2, &
        [size(ncorr, 1, kind=hsize_t), size(ncorr, 2, kind=hsize_t)], ncorr, ierr)
    call H5Dopen_f(corrfileio, DSETNAME_NCORR, dset_ncorr, ierr)
    call H5LTset_attribute_string_f(corrfileio, DSETNAME_NCORR, ATTR_UNIT, "nm$^2$ ps$^{-2}$", ierr)

    if (is_sd) then
      !create a group for storing spatial-decomposition data
      call H5Gcreate_f(corrfileio, GROUP_SPATIAL, grp_sd_id, ierr)

      !decCorr
      call H5LTmake_dataset_double_f(grp_sd_id, DSETNAME_DECCORR, 3, &
          [size(sdcorr, 1, kind=hsize_t), size(sdcorr, 2, kind=hsize_t), size(sdcorr, 3, kind=hsize_t)], sdcorr, ierr)
      call H5Dopen_f(grp_sd_id, DSETNAME_DECCORR, dset_sdcorr, ierr)
      call H5LTset_attribute_string_f(grp_sd_id, DSETNAME_DECCORR, ATTR_UNIT, "nm$^2$ ps$^{-2}$", ierr)

      !decPairCount
      call H5LTmake_dataset_double_f(grp_sd_id, DSETNAME_DECPAIRCOUNT, 2, &
          [size(sdpaircount, 1, kind=hsize_t), size(sdpaircount, 2, kind=hsize_t)], sdpaircount, ierr)
      call H5Dopen_f(grp_sd_id, DSETNAME_DECPAIRCOUNT, dset_sdpaircount, ierr)

      !decBins
      call H5LTmake_dataset_double_f(grp_sd_id, DSETNAME_DECBINS, 1, [size(rbins, kind=hsize_t)], rbins, ierr)
      call H5Dopen_f(grp_sd_id, DSETNAME_DECBINS, dset_rbins, ierr)
      call H5LTset_attribute_string_f(grp_sd_id, DSETNAME_DECBINS, ATTR_UNIT, "nm", ierr)
    end if

    if (is_ed) then
      !create a group for storing energy-decomposition data
      call H5Gcreate_f(corrfileio, GROUP_ENERGY, grp_ed_id, ierr)

      !decCorr
      call H5LTmake_dataset_double_f(grp_ed_id, DSETNAME_DECCORR, 3, &
          [size(edcorr, 1, kind=hsize_t), size(edcorr, 2, kind=hsize_t), size(edcorr, 3, kind=hsize_t)], edcorr, ierr)
      call H5Dopen_f(grp_ed_id, DSETNAME_DECCORR, dset_edcorr, ierr)
      call H5LTset_attribute_string_f(grp_ed_id, DSETNAME_DECCORR, ATTR_UNIT, "nm$^2$ ps$^{-2}$", ierr)

      !decPairCount
      call H5LTmake_dataset_double_f(grp_ed_id, DSETNAME_DECPAIRCOUNT, 2, &
          [size(edpaircount, 1, kind=hsize_t), size(edpaircount, 2, kind=hsize_t)], edpaircount, ierr)
      call H5Dopen_f(grp_ed_id, DSETNAME_DECPAIRCOUNT, dset_edpaircount, ierr)

      !decBins
      call H5LTmake_dataset_double_f(grp_ed_id, DSETNAME_DECBINS, 1, [size(ebins, kind=hsize_t)], ebins, ierr)
      call H5Dopen_f(grp_ed_id, DSETNAME_DECBINS, dset_ebins, ierr)
      call H5LTset_attribute_string_f(grp_ed_id, DSETNAME_DECBINS, ATTR_UNIT, "kcal mol$^{-1}$", ierr)
    end if

    !attach scale dimension
    !dimension index is ordered in row major as (dimN, dimN-1, ..., dim2, dim1)
    call H5DSattach_scale_f(dset_ncorr, dset_timeLags, 2, ierr)
    if (is_sd) then
      call H5DSattach_scale_f(dset_sdcorr, dset_timeLags, 3, ierr)
      call H5DSattach_scale_f(dset_sdcorr, dset_rbins, 2, ierr)
      call H5DSattach_scale_f(dset_sdpaircount, dset_rbins, 2, ierr)
    end if
    if (is_ed) then
      call H5DSattach_scale_f(dset_edcorr, dset_timeLags, 3, ierr)
      call H5DSattach_scale_f(dset_edcorr, dset_ebins, 2, ierr)
      call H5DSattach_scale_f(dset_edpaircount, dset_ebins, 2, ierr)
    end if

    call H5Dclose_f(dset_timeLags, ierr)
    call H5Dclose_f(dset_ncorr, ierr)
    if (is_sd) then
      call H5Dclose_f(dset_rbins, ierr)
      call H5Dclose_f(dset_sdcorr, ierr)
      call H5Dclose_f(dset_sdpaircount, ierr)
    end if
    if (is_ed) then
      call H5Dclose_f(dset_ebins, ierr)
      call H5Dclose_f(dset_edcorr, ierr)
      call H5Dclose_f(dset_edpaircount, ierr)
    end if
    call H5Fclose_f(corrfileio, ierr)
    call H5close_f(ierr)
  end subroutine output_corr

  subroutine finish()
    deallocate(ncorr, charge, vel_r, vel_c, start_index)
    if (is_sd) call sd_finish()
    if (is_ed) call ed_finish()
  end subroutine finish

  integer function count_arg(i, num_arg)
    integer, intent(in) :: i, num_arg
    character(len=line_len) :: arg
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
          write(*,*) "Error: unable to count the number of arguments for the ", i-1, "-th option"
          call print_usage()
          call mpi_abend()
        end if
      else if (arg(1:1) == '-' ) then
        is_numeric = verify(arg(2:2), '0123456789') .eq. 0
        if (.not. is_numeric) return !end of data file arguments
      end if
      j = j + 1
      count_arg = count_arg + 1
    end do
  end function count_arg

  real(dp) function getTfromLog(logfile)
    character(len=*), intent(in) :: logfile
    integer :: logio, idx, temp_idx, stat
    integer, parameter :: RECORD_LEN = 15
    character(len=line_len) :: line
    logical :: found_average

    found_average = .false.
    open(newunit=logio, file=logfile, status='old', action="READ", form="FORMATTED")
    do while(.true.)
      read(logio, "(A"//line_len_str//")", iostat=stat) line
      if (stat > 0) then
        write(*,*) "Error reading line"
        call exit(1)
      else if (stat < 0) then
        write(*,*) "Unable to find 'A V E R A G E S' in logfile ", trim(adjustl(logfile))
        call exit(1)
      end if

      if (found_average) then
        idx = index(line, "Temperature")
        if (idx > 0) then
          temp_idx = ceiling(real(idx, dp) / RECORD_LEN)
          read(logio, "(A"//line_len_str//")", iostat=stat) line
          if (stat > 0) then
            write(*,*) "Error reading temperature record"
            call exit(1)
          end if
          read(line(RECORD_LEN * (temp_idx - 1) + 1: RECORD_LEN * temp_idx), *) getTfromLog
          return
        end if
      else
        idx = index(line, "A V E R A G E S")
        if (idx > 0) then
          found_average = .true.
        end if
      end if
    end do
  end function getTfromLog

  integer function getMolTypeIndex(i, numMol, nummoltype)
    integer, intent(in) :: i, numMol(:), nummoltype
    integer :: n, numMol_acc

    getMolTypeIndex = -1
    numMol_acc = 0
    do n = 1, nummoltype
      numMol_acc = numMol_acc + numMol(n)
      if (i <= numMol_acc) then
        getMolTypeIndex = n
        return
      end if
    end do
  end function getMolTypeIndex

  integer function getMolTypePairIndex(i, j, numMol, nummoltype)
    integer, intent(in) :: i, j, numMol(:), nummoltype
    integer :: r, c, ii, jj
    !          c
    !    | 1  2  3  4
    !  --+------------
    !  1 | 1  2  3  4
    !    |
    !  2 |    5  6  7
    !r   |
    !  3 |       8  9
    !    |
    !  4 |         10
    !
    !  index(r, c) = (r - 1) * n + c - r * (r - 1) / 2
    !  where n = size(c) = size(r), r <= c


    ii = getMolTypeIndex(i, numMol, nummoltype)
    jj = getMolTypeIndex(j, numMol, nummoltype)
    r = min(ii, jj)
    c = max(ii, jj)
    getMolTypePairIndex = (r - 1) * nummoltype + c - r * (r - 1) / 2
  end function getMolTypePairIndex

  subroutine com_vel(com_v, vel, start_index)
    real(dp), dimension(:, :), intent(out) :: com_v
    real(dp), dimension(:, :), intent(in) :: vel
    integer, dimension(:), intent(in) :: start_index
    integer :: d, i, j, idx_begin, idx_end, idx_com

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

  subroutine print_usage()
    write(*, *) "usage: $ decond <trrfile> <logfile> <numFrameToRead> <-pa | -pm ...> [options]"
    write(*, *) "options: "
    write(*, *) "  -pa <topfile.top> <molecule1> <start_index1> [<molecule2> <start_index2>...]:"
    write(*, *) "   read parameters from topology file. ignored when -pm is given"
    write(*, *)
    write(*, *) "  -pm <molecule1> <charge1> <number1> [<molecule2> <charge2> <number2>...]:"
    write(*, *) "   manually assign parameters for single-atom-molecule system"
    write(*, *)
    write(*, *) "  -o <outfile>: output filename. default = corr.h5"
    write(*, *)
    write(*, *) "  -skiptrj <skip>: skip=1 means no frames are skipped, which is default."
    write(*, *) "             skip=2 means reading every 2nd frame."
    write(*, *)
    write(*, *) "  -skipeng <skip>: skip=1 means no frames are skipped, which is default."
    write(*, *) "             skip=2 means reading every 2nd frame."
    write(*, *)
    write(*, *) "  -l <maxlag>: maximum time lag in frames. default = <numFrameToRead - 1>"
    write(*, *)
    write(*, *) "  -sd: do spatial decomposition. default no sd."
    write(*, *)
    write(*, *) "  -ed <engtraj> <engtraj> ...: do energy decomposition. default no ed."
    write(*, *)
    write(*, *) "  -sbwidth <sBinWidth(nm)>: spatial-decomposition bin width. default = 0.01."
    write(*, *) "                            only meaningful when -sd is given."
    write(*, *)
    write(*, *) "  -ebwidth <ebinwidth(kcal/mol)>: energy-decomposition bin width. default = 0.1"
    write(*, *) "                                  only meaningful when -ed is given."
    write(*, *)
    write(*, *) "  -d <num_domain_r> <num_domain_c>:"
    write(*, *) "   manually assign the MPI decomposition pattern"
  end subroutine print_usage
end module manager
