!> \file planets.f90  Procedures to compute planet positions and more for libTheSky


!  Copyright (c) 2002-2013  AstroFloyd - astrofloyd.org
!   
!  This file is part of the libTheSky package, 
!  see: http://libthesky.sf.net/
!   
!  This is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
!  as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
!  
!  This software is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
!  warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
!  
!  You should have received a copy of the GNU General Public License along with this code.  If not, see 
!  <http://www.gnu.org/licenses/>.


!***********************************************************************************************************************************
!> \brief Procedures for planets

module TheSky_planets
  implicit none
  save
  
  
contains
  
  
  !*********************************************************************************************************************************
  !> \brief  Compute the position, distance, etc of a planet
  !!
  !! \param jd  Julian date of computation
  !! \param pl  Planet number: Moon=0, Merc=1,Nep=8,Plu=9 3=Sun, 0=Moon, >10 for other objects
  
  subroutine planet_position(jd,pl)
    use SUFR_kinds, only: double
    use SUFR_constants, only: pi, au,earthr,pland, enpname
    use SUFR_system, only: warn
    use SUFR_angles, only: rev, rev2
    use SUFR_astro, only: calcgmst
    use SUFR_dummy, only: dumdbl
    
    use TheSky_vsop, only: vsop_lbr
    use TheSky_local, only: lon0, lat0, deltat
    use TheSky_coordinates, only: ecl_2_eq, eq2horiz, hc_spher_2_gc_rect, geoc2topoc_ecl, rect_2_spher
    use TheSky_coordinates, only: precess_ecl, fk5, aberration_ecl
    use TheSky_nutation, only: nutation, nutation2000
    use TheSky_moon, only: moon_lbr, moonmagn
    use TheSky_comets, only: cometgc
    use TheSky_planetdata, only: planpos
    use TheSky_cometdata, only: cometElems
    use TheSky_asteroids, only: asteroid_magn, asteroid_lbr
    use TheSky_datetime, only: calc_deltat
    
    implicit none
    real(double), intent(in) :: jd
    integer, intent(in) :: pl
    integer :: j
    real(double) :: tjm,jde,tjm0,  dpsi,eps0,deps,eps,tau,tau1
    real(double) :: hcl0,hcb0,hcr0, hcl,hcb,hcr, hcl00,hcb00,hcr00, sun_gcl,sun_gcb, gcx,gcy,gcz, gcx0,gcy0,gcz0, dhcr
    real(double) :: gcl,gcb,delta,gcl0,gcb0,delta0
    real(double) :: ra,dec,gmst,agst,lst,hh,az,alt,elon,  topra,topdec,topl,topb,topdiam,topdelta,tophh,topaz,topalt
    real(double) :: diam,illfr,pa,magn,  parang,hp,res1,res2
    
    ! Make sure these are always defined:
    gcl0 = 0.d0;  gcb0 = 0.d0;  hcr00 = 0.d0
    gcx  = 0.d0;  gcy  = 0.d0;  gcz  = 0.d0
    gcx0 = 0.d0;  gcy0 = 0.d0;  gcz0 = 0.d0
    topdelta = 0.d0;  delta0 = 0.d0
    diam = 0.d0
    magn = 0.d0  ! Make sure magn is always defined
    
    ! Calc JDE & t:
    deltat = calc_deltat(jd)
    jde    = jd + deltat/86400.d0
    tjm    = (jde-2451545.d0)/365250.d0                                ! Julian Millennia after 2000.0 in dyn. time, tau in Meeus
    tjm0   = tjm
    
    call vsop_lbr(tjm,3, hcl0,hcb0,hcr0)                               ! Calculate the Earth's true heliocentric l,b,r
    
    
    
    ! Iterate to get the light time tau, hence apparent positions:
    tau  = 6.d-3                                                       ! Light distance in days - typical planet: ~500s ~ 0.006 days
    tau1 = 0.d0                                                        ! On first iteration, tau=0 to get true positions
    j = 0                                                              ! Takes care of escape in case of infinite loop
    do while(abs((tau-tau1)/tau).gt.1.d-10)                            ! Moon's tau ~10^-5; 1.d-10~10^-5 sec, 1.d-7~10^-2 sec
       
       tau = tau1                                                      ! On first iteration, tau=0 to get true positions
       tjm = tjm0 - tau/365250.d0                                      ! Iterate to calculate light time
       hcl = 0.d0; hcb = 0.d0; hcr = 0.d0                              ! Heliocentric coordinates
       
       
       ! Compute l,b,r for planet, Pluto, asteroid, Earth's shadow:
       if(pl.gt.0.and.pl.lt.9) call vsop_lbr(tjm,pl, hcl,hcb,hcr)      ! Heliocentric l,b,r
       if(pl.eq.9) call plutolbr(tjm*10.d0,hcl,hcb,hcr)                ! This is for 2000.0, precess 10 lines below
       if(pl.gt.10000) call asteroid_lbr(tjm,pl-10000,hcl,hcb,hcr)     ! Heliocentric lbr for asteroids
       if(pl.eq.-1) then                                               ! Centre of Earth's shadow
          call vsop_lbr(tjm,3,hcl,hcb,hcr)                             ! = heliocentric coordinates ...
          call moon_lbr(tjm, dumdbl,dumdbl,dhcr)                       ! only want dhcr
          hcr = hcr + dhcr                                             ! + distance Earth-Moon
       end if
       
       
       ! Compute geocentric ecliptical position:
       if(pl.eq.0) call moon_lbr(tjm,gcl,gcb,delta)                    ! Get apparent geocentric coordinates of the Moon
       if(pl.ne.0.and.pl.lt.10 .or. pl.gt.10000) then                  ! Planet, asteroid, Earth's shadow
          
          ! For Neptune's birthday:
          !print*,'TESTING!!!'
          !call precess_ecl(jde,2451545.d0,hcl,hcb)                     ! from JoD to J2000.0
          
          call hc_spher_2_gc_rect(hcl,hcb,hcr, hcl0,hcb0,hcr0, gcx,gcy,gcz)  ! Convert heliocentric l,b,r to geocentric x,y,z
          call rect_2_spher(gcx,gcy,gcz, gcl,gcb,delta)                      ! Convert geocentric x,y,z to geocentric l,b,r
          if(pl.eq.3) delta = hcr
          if(pl.eq.9) call precess_ecl(2451545.d0,jde,gcl,gcb)         ! Pluto:  from J2000.0 to JoD
       end if
       
       if(pl.gt.10.and.pl.lt.10000) &
            call cometgc(tjm,tjm0, pl, hcr,gcl,gcb,delta)              ! Calc geocentric l,b,r coordinates for a comet
       
       
       ! Store 'true' position, for tau=0:
       if(j.eq.0) then
          if(abs(tau).gt.1.d-10) call warn('planet_position():  tau != 0 on first light-time iteration', 0)
          
          hcl00  = hcl                                                 ! Heliocentric l,b,r
          hcb00  = hcb
          hcr00  = hcr
          
          gcx0   = gcx                                                 ! Geocentric x,y,z
          gcy0   = gcy
          gcz0   = gcz
          
          delta0 = delta                                               ! Geocentric l,b,r
          gcl0   = gcl
          gcb0   = gcb
       end if
       
       tau1 = 5.77551830441d-3 * delta                                 ! Light time in days
       
       j = j+1
       if(j.ge.30) then
          call warn('planet_position():  Light time failed to converge for '//trim(enpname(pl)), 0)
          exit
       end if
    end do
    
    tau = tau1
    tjm = tjm0                                                  ! Still Julian Millennia since 2000.0 in dynamical time
    
    if(pl.eq.-1) call moon_lbr(tjm, dumdbl,dumdbl,delta)        ! Geocentric distance of the Moon for Earth shadow; only need delta
    
    if(pl.eq.3) then                                            ! This seems true, but appears to be apparent?!?!?
       gcl   = rev(hcl0+pi)
       gcb   = -hcb0
       delta = hcr
    end if
    
    
    ! Correct for nutation and aberration, and convert to FK5:
    call nutation(tjm,dpsi,eps0,deps)  ! dpsi: nutation in longitude, deps: in obliquity
    call nutation2000(jd,dpsi,deps)    ! IAU 2000 Nutation model, doesn't provide eps0(?)
    eps = eps0 + deps                  ! Correct for nutation: mean -> true obliquity of the ecliptic
    
    if(pl.lt.10) then  ! I suppose this should also happen for comets, but this compares better...
       if(pl.ne.0) call aberration_ecl(tjm,hcl0, gcl,gcb)
       call fk5(tjm, gcl,gcb)
       gcl = gcl + dpsi  ! Nutation
    end if
    
    ! sun_gcl,sun_gcb give gcl,gcb as if pl.eq.3
    sun_gcl = rev(hcl0+pi)
    sun_gcb = -hcb0
    
    ! Aberration, FK5 and nutation for sun_gcl,sun_gcb:
    call aberration_ecl(tjm,hcl0, sun_gcl,sun_gcb)
    call fk5(tjm, sun_gcl,sun_gcb)
    sun_gcl = rev(sun_gcl + dpsi)  ! Nutation in longitude
    
    ! FK5 conversion for l,b, hcl0,hcb0, hcl00,hcb00:
    call fk5(tjm, hcl,hcb)
    call fk5(tjm, hcl0,hcb0)
    call fk5(tjm, hcl00,hcb00)
    
    
    ! Convert geocentric ecliptical to equatorial coordinates:
    call ecl_2_eq(gcl,gcb,eps, ra,dec)    ! RA, Dec
    
    
    ! Siderial time:
    gmst = calcgmst(jd)                   ! Greenwich mean siderial time
    agst = rev(gmst + dpsi*cos(eps))      ! Correction for equation of the equinoxes -> Greenwich apparent siderial time
    lst  = rev(agst + lon0)               ! Local apparent stellar time, lon0 > 0 for E
    
    
    ! Apparent diameter:
    if(pl.ge.0.and.pl.lt.10) diam = atan(pland(pl)/(delta*au))
    !if(pl.lt.10.and.pl.ge.0) diam = atan(planr(pl)/(2*delta*au))*2
    if(pl.eq.-1) then
       call earthshadow(delta,hcr0,res1,res2)  ! Calc Earth shadow radii at Moon distance
       diam = 2*res1                           ! Core-shadow diameter to planpos(12)
    end if
    
    ! Comets:
    if(pl.gt.10) then
       diam = 0.d0
       magn = cometElems(pl,8) + 5*log10(delta) + 2.5d0*cometElems(pl,9)*log10(hcr)
       topdelta = delta
    end if
    
    ! Convert heliocentric to topocentric coordinates:
    call geoc2topoc_ecl(gcl,gcb,delta,diam/2.d0,eps,lst, topl,topb,topdiam)             ! Geocentric to topocentric: l, b, diam
    if(pl.eq.-1) topdiam = res2                                                         ! Earth penumbra radius at Moon distance
    topdiam = 2*topdiam
    if(pl.ge.0.and.pl.lt.10) topdelta = pland(pl)/tan(topdiam)/au
    
    
    ! Convert equitorial to horizontal coordinates:
    call eq2horiz(ra,dec,agst, hh,az,alt)
    
    
    ! Elongation:
    elon = acos(cos(gcb)*cos(hcb0)*cos(gcl-rev(hcl0+pi)))
    if(pl.eq.3) elon = 0.d0
    if(pl.gt.10) elon = acos((hcr0**2 + delta**2 - hcr**2)/(2.d0*hcr0*delta))        ! For comets (only?)
    
    ! Convert topocentric coordinates: ecliptical -> equatorial -> horizontal:
    !call geoc2topoc_eq(ra,dec,delta,hh,topra,topdec)                            ! Geocentric to topocentric
    call ecl_2_eq(topl,topb,eps, topra,topdec)                                   ! Topocentric l,b -> RA,dec - probably cheaper
    call eq2horiz(topra,topdec,agst, tophh,topaz,topalt)
    
    ! Phase angle:
    pa = 0.d0  ! Make sure pa is always defined
    if(pl.eq.0) then
       pa = atan2( hcr0*sin(elon) , delta - hcr0*cos(elon) )         ! Moon
    else if(pl.gt.0) then
       pa = acos( (hcr**2 + delta**2 - hcr0**2) / (2*hcr*delta) )    ! Planets
       if(pl.eq.3) pa = 0.d0                                         ! Sun
    end if
    illfr = 0.5d0*(1.d0 + cos(pa))                                   ! Illuminated fraction of the disc
    
    
    ! Compute magnitude:
    if(pl.gt.0.and.pl.lt.10) magn = planet_magnitude(pl,hcr,delta,pa)
    if(pl.eq.0) magn = moonmagn(pa,delta)                          ! Moon
    if(pl.eq.6) magn = satmagn(tjm*10.,gcl,gcb,delta,hcl,hcb,hcr)  ! Calculate Saturn's magnitude
    if(pl.gt.10000) magn = asteroid_magn(pl-10000,delta,hcr,pa)     ! Asteroid magnitude (valid for |pa|<120deg
    
    
    ! Parallactic angle:
    !parang = atan2(sin(hh),tan(lat0)*cos(dec) - sin(dec)*cos(hh))              ! Parallactic angle: geocentric
    parang = atan2(sin(tophh),tan(lat0)*cos(topdec) - sin(topdec)*cos(tophh))   ! Parallactic angle: topocentric
    
    
    ! Horizontal parallax:
    hp = asin(earthr/(delta*au))                                                ! Horizontal parallax
    
    
    ! Overrule some values:
    if(pl.eq.0) hcr    = 0.d0
    if(pl.eq.3) then
       magn  = sunmagn(delta)                                                   ! Changes ~0.05 over half a year...
       illfr = 1.                                                               ! Illuminated fraction
    end if
    
    
    
    
    ! Save variables:
    ! Geocentric:
    planpos     = 0.d0              ! 1-12 are geocentric, repeated as topocentric in 21-32
    planpos(1)  = rev(gcl)          ! Ecliptic longitude
    planpos(2)  = rev2(gcb)         ! Ecliptic latitude
    planpos(3)  = hcr               ! Distance to the Sun
    planpos(4)  = delta             ! Apparent geocentric distance
    planpos(5)  = rev(ra)           ! R.A.
    planpos(6)  = dec               ! Declination
    planpos(7)  = tau               ! Light time in days
    planpos(8)  = rev(hh)           ! Hour angle
    planpos(9)  = rev(az)           ! Azimuth
    planpos(10) = alt               ! Altitude
    planpos(11) = rev(elon)         ! Elongation
    planpos(12) = diam              ! Apparent diameter
    
    planpos(13) = magn              ! Apparent visual magnitude
    planpos(14) = illfr             ! Illuminated fraction
    planpos(15) = rev(pa)           ! Phase angle
    planpos(16) = parang            ! Topocentric parallactic angle
    planpos(17) = hp                ! Horizontal parallax
    
    ! Topocentric:
    planpos(21) = rev(topl)   
    planpos(22) = rev2(topb)
    planpos(23) = delta0            ! True geocentric distance
    planpos(24) = topdelta
    planpos(25) = rev(topra)
    planpos(26) = topdec
    
    planpos(28) = rev(tophh)        ! Hour angle
    planpos(29) = rev(topaz)
    planpos(30) = topalt
    
    planpos(32) = topdiam
    
    ! Heliocentric:
    planpos(33) = rev(hcl)          ! Heliocentric apparent l,b,r
    planpos(34) = rev2(hcb) 
    planpos(35) = hcr               
    planpos(36) = rev(hcl00)        ! Heliocentric true l,b,r
    planpos(37) = rev2(hcb00)
    planpos(38) = hcr00
    
    ! Other variables:
    planpos(39) = dble(pl)          ! Remember for which planet data were computed
    planpos(40) = jde               ! JDE for these data
    planpos(41) = rev(hcl0+pi+dpsi) ! Geocentric, true L,B,R for the Sun, in FK5, corrected for nutation
    planpos(42) = rev2(-hcb0)
    planpos(43) = hcr0
    planpos(44) = lst               ! Local APPARENT stellar time
    planpos(45) = rev(agst)         ! Greenwich APPARENT siderial time (in radians)
    planpos(46) = tjm0 * 10.d0      ! Apparent dynamical time in Julian Centuries since 2000.0
    planpos(47) = dpsi              ! Nutation in longitude
    planpos(48) = eps               ! True obliquity of the ecliptic; corrected for nutation
    planpos(49) = rev(gmst)         ! Greenwich MEAN siderial time (in radians)
    planpos(50) = eps0              ! Mean obliquity of the ecliptic; without nutation
    
    ! Geocentric:
    planpos(51) = rev(sun_gcl)      ! Apparent geocentric longitude of the Sun (variable was treated as if pl.eq.3)
    planpos(52) = rev2(sun_gcb)     ! Apparent geocentric latitude of the Sun (variable was treated as if pl.eq.3)
    
    planpos(61) = gcx               ! Apparent geocentric x,y,z
    planpos(62) = gcy
    planpos(63) = gcz
    planpos(64) = gcx0              ! True geocentric x,y,z
    planpos(65) = gcy0
    planpos(66) = gcz0
    planpos(67) = gcl0              ! True geocentric l,b,r
    planpos(68) = gcb0
    planpos(69) = delta0
    
  end subroutine planet_position
  !*********************************************************************************************************************************
  
  
  
  
  
  
  !*********************************************************************************************************************************
  !> \brief  Calculate Pluto's position l,b,r at time t
  !! 
  !! \param  t   Dynamical time in Julian Centuries after 2000.0
  !! \retval l   Heliocentric longitude (rad)
  !! \retval b   Heliocentric latitude (rad)
  !! \retval r   Heliocentric distance (AU?)
  
  subroutine plutolbr(t,l,b,r)
    use SUFR_kinds, only: double
    use SUFR_constants, only: d2r
    use TheSky_planetdata, only: pluc,plul,plub,plur
    
    implicit none
    real(double), intent(in) :: t
    real(double), intent(out) :: l,b,r
    integer :: i
    real(double) :: j,s,p,a, cosa,sina
    
    j =  34.35d0 + 3034.9057d0 * t
    s =  50.08d0 + 1222.1138   * t
    p = 238.96d0 + 144.96d0    * t
    
    l = 0.d0
    b = 0.d0
    r = 0.d0
    
    do i=1,43
       a = (pluc(i,1)*j + pluc(i,2)*s + pluc(i,3)*p) * d2r
       cosa = cos(a)
       sina = sin(a)
       l = l + plul(i,1)*sina + plul(i,2)*cosa
       b = b + plub(i,1)*sina + plub(i,2)*cosa
       r = r + plur(i,1)*sina + plur(i,2)*cosa
    end do
    
    l = ( l*1.d-6 + 238.958116d0  + 144.96d0*t ) * d2r
    b = ( b*1.d-6 -   3.908239d0               ) * d2r
    r =   r*1.d-7 +  40.7241346d0
    
  end subroutine plutolbr
  !*********************************************************************************************************************************
  
  
  
  
  !*********************************************************************************************************************************
  !> \brief  Calculate orbital elements for the planets
  !!
  !! \param jd  Julian day of calculation
  !!
  !! \note
  !! Results are returned through the module planetdata, for planet pl and element el:
  !! - plelems(pl,el):     EoD
  !! - plelems2000(pl,el): J2000.0
  !!
  !! Elements (el):
  !! - 1: L     - mean longitude
  !! - 2: a     - semi-major axis
  !! - 3: e     - eccentricity
  !! - 4: i     - inclination
  !! - 5: Omega - longitude of ascending node
  !! - 6: pi    - longitude of perihelion
  
  subroutine planetelements(jd)
    use SUFR_kinds, only: double
    use SUFR_constants, only: d2r
    use SUFR_system, only: quit_program_error
    use SUFR_angles, only: rev
    
    use TheSky_local, only: deltat
    use TheSky_planetdata, only: plelems, plelems2000, plelemdata
    use TheSky_datetime, only: calc_deltat
    
    implicit none
    real(double), intent(in) :: jd
    integer :: el,pl,te
    real(double) :: jde,tm,tms(0:3)
    
    if(plelemdata(1,1,1,1).eq.0.d0)  call quit_program_error('planetelements():  did you forget to call readplanetelements()?', 0)
    
    deltat = calc_deltat(jd)
    jde = jd + deltat/86400.d0
    tm = (jde-2451545.d0)/36525.d0                 ! Julian Centuries after 2000.0 in dynamical time
    
    
    ! Powers of tm:
    do te=0,3
       tms(te) = tm**te
    end do
    
    
    do pl=1,8
       do el=1,6
          
          plelems(pl,el) = 0.d0
          plelems2000(pl,el) = 0.d0
          
          do te=0,3
             plelems(pl,el)     = plelems(pl,el)     + plelemdata(1,pl,el,te) * tms(te)
             plelems2000(pl,el) = plelems2000(pl,el) + plelemdata(2,pl,el,te) * tms(te)
          end do
          
          if(el.ne.2.and.el.ne.3) then
             plelems(pl,el)     = rev(plelems(pl,el)     * d2r)
             plelems2000(pl,el) = rev(plelems2000(pl,el) * d2r)
          end if
          
       end do
    end do
    
  end subroutine planetelements
  !*********************************************************************************************************************************
  
  
  
  
  !*********************************************************************************************************************************
  !> \brief  Calculate planet magnitude
  !!
  !! \param pl          Planet ID
  !! \param r           Distance from the Sun (AU)
  !! \param d           Distance from the Earth (AU)
  !! \param par         Phase angle (rad)
  !!
  !! \retval magnitude  Apparent planet magnitiude
  !!
  !! \see  Meeus, Astronomical Algorithms, 1998, Ch.41
  
  function planet_magnitude(pl,r,d,par)
    use SUFR_kinds, only: double
    use SUFR_constants, only: r2d
    
    implicit none
    integer, intent(in) :: pl
    real(double), intent(in) :: r,d,par
    real(double) :: planet_magnitude,pa,pa2,pa3,a0(9),a1(9),a2(9),a3(9)
    
    ! PA must be in degrees:
    pa  = par*r2d
    if(pl.eq.1) pa = pa - 50.d0  ! For Mercury (deg) -- ONLY FOR METHOD 1 !!!
    pa2 = pa*pa
    pa3 = pa*pa2
    
    ! Method 1 - Meeus p.285:
    a0 = (/-1.16d0,  4.d0,     0.d0, 1.3d0,   8.93d0, 8.7d0, 6.85d0, 7.05d0, 1.d0/) * (-1)
    a1 = (/ 2.838d0, 1.322d0,  0.d0, 1.486d0, 0.d0,   0.d0,  0.d0,   0.d0,   0.d0/) * 1.d-2
    a2 = (/ 1.023d0, 0.d0,     0.d0, 0.d0,    0.d0,   0.d0,  0.d0,   0.d0,   0.d0/) * 1.d-4
    a3 = (/ 0.d0,    0.4247d0, 0.d0, 0.d0,    0.d0,   0.d0,  0.d0,   0.d0,   0.d0/) * 1.d-6
    
    planet_magnitude = 5.d0*log10(r*d) + a0(pl) + a1(pl)*pa + a2(pl)*pa2 + a3(pl)*pa3
    
    
    ! Method 2 - Meeus p.286:
    ! a0 = (/ 0.42d0, 4.4d0,  0.d0, 1.52d0, 9.4d0, 8.88d0, 7.19d0, 6.87d0, 1.d0/) * (-1)
    ! a1 = (/ 3.8d0,  0.09d0, 0.d0, 1.6d0,  0.5d0, 0.d0,   0.d0,   0.d0,   0.d0/) * 1.d-2
    ! a2 = (/-2.73d0, 2.39d0, 0.d0, 0.d0,   0.d0,  0.d0,   0.d0,   0.d0,   0.d0/) * 1.d-4
    ! a3 = (/ 2.d0,   0.65d0, 0.d0, 0.d0,   0.d0,  0.d0,   0.d0,   0.d0,   0.d0/) * 1.d-6
    !
    ! planet_magnitude = 5.d0*log10(r*d) + a0(pl) + a1(pl)*pa + a2(pl)*pa2 + a3(pl)*pa3
    
  end function planet_magnitude
  !*********************************************************************************************************************************
  
  
  
  
  !*********************************************************************************************************************************
  !> \brief  Calculate Sun magnitude
  !!
  !! \param  dist     Distance (AU)
  !! \retval sunmagn  Sun magnitude
  
  function sunmagn(dist)
    use SUFR_kinds, only: double
    
    implicit none
    real(double), intent(in) :: dist
    real(double) :: sunmagn,ill
    
    ill = 10.d0**(-0.4d0 * (-26.73d0)) / (dist*dist)  ! Dist in AU, assume average dist = 1
    sunmagn = -2.5d0*log10(ill) 
    
  end function sunmagn
  !*********************************************************************************************************************************
  
  
  !*********************************************************************************************************************************
  !> \brief  Calculate Saturn magnitude
  !!
  !! \param t   Dynamical time in Julian centuries after J2000.0
  !!
  !! \param gl  Geocentric longitude (rad)
  !! \param gb  Geocentric latitude (rad)
  !! \param d   Geocentric distance (AU)
  !!
  !! \param l   Heliocentric longitude (rad)
  !! \param b   Heliocentric latitude (rad) 
  !! \param r   Heliocentric distance (AU)
  !!
  !! \see Meeus, Astronomical Algorithms, 1998, Ch.41
  
  function satmagn(t, gl,gb,d, l,b,r)
    use SUFR_kinds, only: double
    use SUFR_constants, only: d2r,r2d
    use SUFR_angles, only: rev2
    
    implicit none
    real(double), intent(in) :: t, gl,gb,d, l,b,r
    real(double) :: satmagn, i,o,bbb,n,ll,bb,u1,u2,du
    
    i = (28.075216d0  - 0.012998d0*t + 4.d-6*t*t)   * d2r
    o = (169.508470d0 + 1.394681d0*t + 4.12d-4*t*t) * d2r
    
    bbb = asin( sin(i)*cos(gb)*sin(gl-o) - cos(i)*sin(gb) )
    n  = (113.6655d0 + 0.8771d0*t)*d2r
    ll = l - 0.01759d0*d2r/r
    bb = b - 7.64d-4*d2r * cos(l-n)/r
    
    u1 = atan2( sin(i)*sin(bb) + cos(i)*cos(bb)*sin(ll-o) , cos(bb)*cos(ll-o) )
    u2 = atan2( sin(i)*sin(gb) + cos(i)*cos(gb)*sin(gl-o) , cos(gb)*cos(gl-o) )
    du = abs(rev2(u1-u2))  ! rev2() is needed because u1 and u2 jump from pi to -pi at different moments
    
    ! Method 1 - Meeus p.285:
    satmagn = -8.68d0 + 5.d0*log10(d*r) + 0.044d0*abs(du)*r2d - 2.60d0*sin(abs(bbb)) + 1.25d0*(sin(bbb))**2
    
    ! Method 2 - Meeus p.286:  - constant difference of 0.2m...(?)
    !satmagn = -8.88d0 + 5.d0*log10(d*r) + 0.044d0*abs(du)*r2d - 2.60d0*sin(abs(bbb)) + 1.25d0*(sin(bbb))**2
    
  end function satmagn
  !*********************************************************************************************************************************
  
  
  !*********************************************************************************************************************************
  !> \brief  Calculate the umbra and penumbra radii of the Earth's shadow 
  !! 
  !! \param dm0  Distance of the Moon (AU?)
  !! \param ds0  Distance of the Sun  (AU)
  !!
  !! \retval r1  Umbra radius at distance of the Moon (rad)
  !! \retval r2  Penumbra radius at distance of the Moon (rad)
  !!
  !! \see  Expl.sup. to the Astronomical Almanac, p.428
  
  subroutine earthshadow(dm0,ds0, r1,r2)
    use SUFR_kinds, only: double
    use SUFR_constants, only: au, earthr,planr
    
    implicit none
    real(double), intent(in) :: dm0,ds0
    real(double), intent(out) :: r1,r2
    real(double) :: rs,re,ds,dm,p1,ps,ss
    
    dm = dm0*au
    ds = ds0*au
    
    re = earthr
    rs = planr(3)
    
    p1 = asin(re/dm) * 0.998340d0        ! Moon parallax, compensated for Earth's atmosphere
    ps = asin(re/ds)                     ! Solar parallax
    ss = asin(rs/ds)                     ! Solar semi-diameter
    
    r1 = 1.02d0 * (p1 + ps - ss)
    r2 = 1.02d0 * (p1 + ps + ss)
    
  end subroutine earthshadow
  !*********************************************************************************************************************************
  
  
  !*********************************************************************************************************************************
  !> \brief  Compute physical data for Jupiter
  !!
  !! \param  jd    Julian day for computation
  !!
  !! \retval de    Jovocentric latitude of the Earth
  !! \retval ds    Jovocentric latitude of the Sun
  !! \retval omg1  Longitude of central meridian of System I (equator+-10deg)
  !! \retval omg2  Longitude of central meridian of System II
  !!
  !! \retval pa    Position angle of Jupiter's north pole (from N to E)
  !! \retval in    Inclination of Jupiter's rotation axis to the orbital plane
  !! \retval om    Longitude of node of Jupiter's equator on ecliptic
  !!
  !! \see Meeus, Astronomical Algorithms, 1998, Ch.43
  
  subroutine jupiterphys(jd,  de,ds, omg1,omg2, pa, in,om)
    use SUFR_kinds, only: double
    use SUFR_constants, only: d2r, jd1900  !,pi
    use SUFR_angles, only: rev
    
    use TheSky_local, only: deltat
    use TheSky_planetdata, only: planpos
    use TheSky_coordinates, only: ecl_2_eq, eq_2_ecl
    use TheSky_datetime, only: calc_deltat
    
    implicit none
    real(double), intent(in) :: jd
    real(double), intent(out) :: de,ds, omg1,omg2, pa, in,om
    real(double) :: jde,d,t1,t2,t3
    real(double) :: alp0,del0,w1,w2,x,y,z,eps0,eps,dpsi,l,b,alps,dels !,r ,l0,b0,r0
    real(double) :: u,v,alp,del,dze,delta,l1,b1  ! ,c
    
    ! To get data for the exact (rounded off) moment of Meeus' example:
    !d = 15690.00068d0
    !jde = d + 2433282.5d0
    !jd = jde - deltat/86400.d0
    
    call planet_position(jd,5)
    call planetelements(jd) 
    
    deltat = calc_deltat(jd)
    jde    = jd + deltat/86400.d0
    
    ! Meeus, step 1:
    d      = jde - 2433282.5d0  ! Since 1950 (!)
    t1     = d/36525.d0  ! In julian centuries
    
    t2     = (jde - jd1900)/36525.d0           ! Time since J1900.0, in Julian centuries
    in = (3.120262d0 + 0.0006d0 * t2) * d2r    ! Inclination of Jupiter's rotation axis to the orbital plane (Meeus, p.311)
    
    t3 = jde - 2443000.5d0 - planpos(7)        ! Days since 1976-08-10 (Meeus, p.305), minus light-travel time
    om = (316.518203d0 - 2.08362d-6*t3) * d2r  ! Long. of node of Jupiter's equator on ecliptic, psi in Meeus, p.306
    om = om + (1.3966626d0*t1 + 3.088d-4*t1**2)*d2r  ! Correct for precession (since B1950, but J1950 will do), Meeus p.311
    
    alp0 = rev((268.d0 + 0.1061d0*t1)*d2r)  ! Right ascension of Jupiter's north pole
    del0 = rev((64.5d0 - 0.0164d0*t1)*d2r)  ! Declination of Jupiter's north pole
    
    ! Meeus, step 2:
    w1 = rev((17.710d0 + 877.90003539d0*d)*d2r)  ! Longitude system I
    w2 = rev((16.838d0 + 870.27003539d0*d)*d2r)  ! Longitude system II
    
    x = planpos(61)  ! Apparent geocentric x
    y = planpos(62)  ! Apparent geocentric y
    z = planpos(63)  ! Apparent geocentric z
    
    l = planpos(33)  ! Heliocentric apparent l
    b = planpos(34)  ! Heliocentric apparent b
    !r = planpos(35)  ! Heliocentric apparent r
    delta = planpos(4)  ! Apparent geocentric distance
    
    !l0 = rev(planpos(41)+pi)  ! Heliocentric, true coordinates of the Earth
    !b0 = -planpos(42)
    !r0 = planpos(43)
    
    ! Meeus, step 8:
    eps0 = planpos(50)  ! Mean obliquity of the ecliptic; without nutation
    eps  = planpos(48)  ! True obliquity of the ecliptic; corrected for nutation
    dpsi = planpos(47)  ! Nutation in longitude
    
    ! Meeus, step 9:
    call ecl_2_eq(l,b,eps, alps,dels)
    
    ! Meeus, step 10:
    ds = -sin(del0)*sin(dels) - cos(del0)*cos(dels)*cos(alp0-alps)  ! Planetocentric declination of the Sun
    
    ! Meeus, step 11:
    u = y*cos(eps0) - z*sin(eps0)
    v = y*sin(eps0) + z*cos(eps0)
    
    alp = rev(atan2(u,x))
    del = atan2(v,sqrt(x*x+u*u))
    dze = rev( atan2( sin(del0)*cos(del)*cos(alp0-alp) - sin(del)*cos(del0) , cos(del)*sin(alp0-alp) ) )
    
    ! Meeus, step 12:
    de = -sin(del0)*sin(del) - cos(del0)*cos(del)*cos(alp0-alp)  ! Planetocentric declination of the Earth
    
    ! Meeus, step 13:
    omg1 = rev(w1 - dze - 5.07033d0*d2r * delta)  ! Longitude of central meridian of System I (equator +- 10deg)
    omg2 = rev(w2 - dze - 5.02626d0*d2r * delta)  ! Longitude of central meridian of System II (higher lat)
    
    ! Meeus, step 14 - phase correction - same sign as sin(l-l0):
    !c = abs( (2*r*delta + r0*r0 - r*r - delta*delta)/(4*r*delta) ) * sin(l-l0)/abs(sin(l-l0))
    
    ! Meeus, steps 16, 17:
    call eq_2_ecl(alp0,del0,eps0, l1,b1)      ! Has to be eps0
    call ecl_2_eq(l1+dpsi,b1,eps, alp0,del0)  ! Has to be eps
    
    ! Meeus, step 18:
    pa = atan2( cos(del0)*sin(alp0-alp) , sin(del0)*cos(del) - cos(del0)*sin(del)*cos(alp0-alp) )  ! PA of Jupiter's north pole
    
  end subroutine jupiterphys
  !*********************************************************************************************************************************
  
  
  !*********************************************************************************************************************************
  !> \brief  Compute physical data for Saturn
  !!
  !! \param  jd    Julian day of computation
  !!
  !! \retval be    Saturnicentric latitude of the Earth
  !! \retval bs    Saturnicentric latitude of the Sun
  !!
  !! \retval pa    Position angle of Saturn's north pole (from N to E)
  !! \retval in    Inclination of Saturn's rotation axis to the orbital plane
  !! \retval om    Longitude of node of Saturn's equator on ecliptic
  !!
  !! \retval ar    Projected major axis of ring (NOT semi-!!!)
  !! \retval br    Projected minor axes of ring (NOT semi-!!!), br has same sign as bs
  !! \retval du    Difference between saturnicentric longitudes of Sun and Earth (NOT abs!!!)
  !! 
  !! \retval pa_s  Position angle of Saturn's north pole (from N to E), as seen from the SUN
  !! \retval ar_s  Projected major axis of ring (NOT semi-!!!), as seen from the SUN
  !! \retval br_s  Projected minor axes of ring (NOT semi-!!!), br has same sign as bs, as seen from the SUN
  !!
  !!
  !! \see Meeus, Astronomical Algorithms, 1998, Ch.45  (The ring of Saturn)
  !!
  !! \todo
  !! - check true/apparent coordinates (see CHECK)
  
  subroutine saturnphys(jd, be,bs, pa, in,om, ar,br, du,  pa_s, ar_s,br_s)
    use SUFR_kinds, only: double
    use SUFR_constants, only: pi, as2r,d2r
    use SUFR_angles, only: rev
    
    use TheSky_planetdata, only: planpos, plelems
    use TheSky_coordinates, only: ecl_2_eq, hc_spher_2_gc_rect, rect_2_spher
    
    implicit none
    real(double), intent(in) :: jd
    real(double), intent(out) :: be,bs, pa, in,om, ar,br, du,  pa_s, ar_s,br_s
    integer :: loop
    real(double) :: t, lam,bet, d,l,b,r, l0,b0,r0, x,y,z, dpsi,eps, ascn
    real(double) :: l2,b2, u1,u2, lam0,bet0, dl,db, ra,dec, ra0,dec0,  sinbe
    
    call planet_position(jd,6)  ! Position of Saturn
    
    ! Meeus, step 3:
    l   =  planpos(33)  ! Heliocentric longitude of Saturn
    b   =  planpos(34)  ! Heliocentric latitude of Saturn
    r   =  planpos(35)  ! Heliocentric distance of Saturn
    
    t    = planpos(46)  ! App. dyn. time in Julian Centuries since 2000.0
    
    ! Meeus, step 10:
    dpsi = planpos(47)  ! Nutation in longitude
    eps  = planpos(48)  ! True obliquity of the ecliptic; corrected for nutation
    
    do loop=1,2  ! From Sun, Earth:
       
       ! Meeus, step 2:
       if(loop.eq.1) then  ! Seen from the Sun:
          lam = l
          bet = b
          d = r
       else  ! Seen from the Earth:
          l0  =  rev(planpos(41)+pi)  ! Geocentric, true L,B,R for the Earth, in FK5  -  CHECK - need apparent?
          b0  = -planpos(42)
          r0  =  planpos(43)
          
          ! Meeus, Ch. 45, step 5:
          call hc_spher_2_gc_rect(l,b,r, l0,b0,r0, x,y,z)
          call rect_2_spher(x,y,z, lam,bet,d)
       end if
       
       ! Meeus, step 1:
       in = (28.075216d0  - 0.012998d0*t + 4.d-6 * t**2)   * d2r  ! Inclination of rotation axis,               Eq. 45.1a
       om = (169.508470d0 + 1.394681d0*t + 4.12d-4 * t**2) * d2r  ! Longitude of asc. node of equator - Omega,  Eq. 45.1b
       
       ! Meeus, step 6:
       sinbe = sin(in)*cos(bet)*sin(lam-om) - cos(in)*sin(bet)
       ar    = 375.35d0*as2r/d  ! Major axis of outer edge of outer ring
       br    = ar*sinbe         ! Minor axis of outer edge of outer ring
       be    = asin(sinbe)      ! B
       
       if(loop.eq.2) then  ! Seen from Earth:
          ! Meeus, step 7:
          call planetelements(jd)
          ascn = plelems(6,5)                     ! Longitude of Saturn's ascending node
          l2 = l - 0.01759d0*d2r / r              ! Correct for the Sun's aberration on Saturn - lon
          b2 = b - 7.64d-4*d2r * cos(l-ascn) / r  ! Correct for the Sun's aberration on Saturn - lat
          
          ! Meeus, step 8:
          bs = asin(sin(in)*cos(b2)*sin(l2-om) - cos(in)*sin(b2))  ! B'
          
          ! Meeus, step 9:
          u1 = atan2(sin(in)*sin(b2)  + cos(in)*cos(b2)*sin(l2-om),   cos(b2)*cos(l2-om))    ! Saturnicentric longitude of the Sun
          u2 = atan2(sin(in)*sin(bet) + cos(in)*cos(bet)*sin(lam-om), cos(bet)*cos(lam-om))  ! Saturnicentric longitude of the Earth
          du = u1-u2
       end if
       
       ! Meeus, step 11:
       lam0 = om - pi/2.d0  ! Ecliptical longitude of Saturn's north pole
       bet0 = pi/2.d0 - in  ! Ecliptical latitude of Saturn's north pole
       
       if(loop.eq.2) then  ! Seen from the Earth:
          ! Meeus, step 12 - correct for the aberration of Saturn:
          dl  = 0.005693d0*d2r * cos(l0-lam)/cos(bet)
          db  = 0.005693d0*d2r * sin(l0-lam)*sin(bet)
          lam = lam + dl
          bet = bet + db
          
          ! Meeus, step 13 - correct for nutation:
          lam0 = lam0 + dpsi
          lam  = lam  + dpsi
       end if
       
       ! Meeus, step 14:
       call ecl_2_eq(lam,bet,eps,   ra,dec)
       call ecl_2_eq(lam0,bet0,eps, ra0,dec0)
       
       ! Meeus, step 15:
       pa = atan2(cos(dec0)*sin(ra0-ra),sin(dec0)*cos(dec) - cos(dec0)*sin(dec)*cos(ra0-ra))  ! Position angle
       
       if(loop.eq.1) then  ! Save data for the Sun's pov:
          pa_s = pa
          ar_s = ar
          br_s = br
       end if
    end do  ! loop=1,2 - from Sun, Earth
    
  end subroutine saturnphys
  !*********************************************************************************************************************************
  
  
  
  
  
  !*********************************************************************************************************************************
  !> \brief  Low-accuracy planet positions - currently available only for Sun and Moon
  !! 
  !! \param jd    Julian Day of computation
  !! \param pl    Planet number: currently 0 (Moon) and 3 (Sun) only  (for other pl, planet_position() is called)
  !! \param calc  Calculate  1: l,b,r, 2: & ra,dec, 3: & gmst,agst, 4: & az,alt
  !! \param nt    Number of terms to use for the calculation (has an effect for Moon only; nt<=60); 
  !!              a smaller nt gives faster, but less accurate results
  
  subroutine planet_position_la(jd, pl,calc,nt)
    use SUFR_kinds, only: double
    use SUFR_constants, only: pi
    use SUFR_angles, only: rev,rev2
    
    use TheSky_planetdata, only: planpos, nplanpos
    use TheSky_moon, only: moonpos_la
    
    implicit none
    real(double), intent(in) :: jd
    integer, intent(in) :: pl,calc,nt
    real(double) :: moondat(nplanpos)
    real(double) :: hcl0,hcb0,hcr0, gcl,gcb,delta, elon,pa,illfr
    
    select case(pl)
    case(0)  ! Moon
       call moonpos_la(jd,calc,nt)  !nt<=60
       
       if(calc.ge.5) then    ! Compute additional planpos members
          moondat = planpos  ! Store Moon data
          
          ! Get some Sun data:
          call sunpos_la(jd,1)
          hcl0 = rev(planpos(1)+pi)  ! Heliocentric longitude of the Earth - want geocentric lon of Sun?
          hcb0 = -planpos(2)         ! Heliocentric latitude of the Earth  - want geocentric lat of Sun?
          hcr0 = planpos(3)
          
          planpos = moondat   ! Restore Moon data:
          gcl   = planpos(1)  ! l
          gcb   = planpos(2)  ! b
          delta = planpos(4)  ! r
          
          elon = acos(cos(gcb)*cos(hcb0)*cos(gcl-rev(hcl0+pi)))
          pa = atan2( hcr0*sin(elon) , delta - hcr0*cos(elon) )            ! Phase angle
          illfr = 0.5d0*(1.d0 + cos(pa))                                   ! Illuminated fraction of the disc
          
          planpos(11) = rev(elon)           ! Elongation
          planpos(14) = illfr               ! Illuminated fraction
          planpos(15) = rev(pa)             ! Phase angle
          
          planpos(41) = rev(hcl0+pi)        ! Geocentric, true L,B,R for the Sun
          planpos(42) = rev2(-hcb0)
          planpos(43) = hcr0
       end if
       
    case(3)  ! Sun
       call sunpos_la(jd,calc)
       
    case default
       call planet_position(jd,pl)  ! Low-accuracy routines not yet available for planets
    end select
    
  end subroutine planet_position_la
  !*********************************************************************************************************************************
  
  
  
  !*********************************************************************************************************************************
  !> \brief  Low-accuracy solar coordinates (~0.01deg)
  !! 
  !! \param jd    Julian Day of computation
  !! \param calc  Calculate:  1: l,b,r,  2: & ra,dec,  3: & gmst,agst,  4: & az,alt
  !!
  !! \see Meeus, Astronomical Algorithms, 1998, Ch.25
  !!
  !! \todo  Check the last term (omg) in eps0
  
  subroutine sunpos_la(jd, calc)
    use SUFR_kinds, only: double
    use SUFR_angles, only: rev
    use SUFR_astro, only: calcgmst
    
    use TheSky_planetdata, only: planpos
    use TheSky_coordinates, only: eq2horiz
    use TheSky_datetime, only: calc_deltat
    
    implicit none
    real(double), intent(in) :: jd
    integer, intent(in) :: calc
    real(double) :: jde,deltat,t,t2,l0,m,e,c,odot,nu,r,omg,lam,b
    real(double) :: ra,dec,ls,lm,eps,eps0,deps,gmst,agst,dpsi,az,alt,hh
    
    deltat = calc_deltat(jd)
    jde = jd + deltat/86400.d0
    t = (jde-2451545.d0)/36525.d0                 ! Julian Centuries after 2000.0 in dynamical time, the T in Meeus, p.163, Eq. 25.1
    t2 = t*t
    
    l0 = 4.895063168d0 + 628.331966786d0 *t + 5.291838d-6    *t2  ! Mean longitude, Eq. 25.2
    m  = 6.240060141d0 + 628.301955152d0 *t - 2.682571d-6    *t2  ! Mean anomaly, Eq. 25.3
    e  = 0.016708634d0 - 0.000042037d0   *t - 0.0000001267d0 *t2  ! Eccentricity of the Earth's orbit, Eq. 25.4
    
    ! Sun's equation of the centre:
    c = (3.34161088d-2 - 8.40725d-5*t - 2.443d-7*t2)*sin(m)  +  (3.489437d-4 - 1.76278d-6*t)*sin(2*m) + 5.044d-6*sin(3*m)
    odot = rev(l0 + c)  ! True longitude
    nu = rev(m + c)     ! True anomaly
    r = 1.000001018d0*(1.d0-e*e)/(1.d0 + e*cos(nu))  ! Heliocentric distance of the Earth / geocentric dist. of the Sun, Eq. 25.5
    
    ! Nutation, aberration:
    omg = 2.18236d0 - 33.75704138d0 * t
    lam = rev(odot - 9.9309d-5 - 8.34267d-5 * sin(omg))  ! Apparent geocentric longitude, referred to the true equinox of date
    b   = 0.d0
    
    planpos(1)  = lam  ! Geocentric longitude
    planpos(2)  = b    ! Geocentric latitude
    planpos(3)  = r    ! Geocentric distance
    planpos(4)  = r    ! Geocentric distance
    planpos(40) = jde  ! JD
    planpos(46) = t    ! App. dyn. time in Julian Centuries since 2000.0
    
    if(calc.eq.1) return
    
    
    ! CHECK - what about the last term?
    eps0 = 0.409092804222d0 - 2.26965525d-4*t - 2.86d-9*t2 + 8.78967d-9*t2*t !+ 4.468d-5*cos(omg)   ! Mean obliquity of the ecliptic
    ls   = 4.89506386655d0 + 62.84528862d0*t  ! Mean long. Sun
    lm   = 3.8103417d0 + 8399.709113d0*t      ! Mean long. Moon
    dpsi = -8.338795d-5*sin(omg) - 6.39954d-6*sin(2*ls) - 1.115d-6*sin(2*lm) + 1.018d-6*sin(2*omg)  ! Nutation in longitude
    deps = 4.46d-5*cos(omg) + 2.76d-6*cos(2*ls) + 4.848d-7*cos(2*lm) - 4.36d-7*cos(2*omg)           ! Nutation in obliquity
    eps  = eps0 + deps                                                                              ! True obliquity of the ecliptic
    ra   = atan2(cos(eps)*sin(lam),cos(lam))  ! Geocentric right ascension, Eq. 25.6
    dec  = asin(sin(eps*sin(lam)))            ! Geocentric declination,     Eq. 25.7
    
    planpos(5)  = ra    ! Geocentric right ascension
    planpos(6)  = dec   ! Geocentric declination
    planpos(47) = dpsi  ! Nutation in longitude
    planpos(48) = eps   ! True obliquity of the ecliptic; corrected for nutation
    planpos(50) = eps0  ! Mean obliquity of the ecliptic; without nutation
    
    if(calc.eq.2) return
    
    
    gmst = calcgmst(jd)               ! Greenwich mean siderial time
    agst = rev(gmst + dpsi*cos(eps))  ! Correction for equation of the equinoxes -> Gr. apparent sid. time
    planpos(45) = rev(agst)           ! Greenwich mean siderial time
    planpos(49) = rev(gmst)           ! Correction for equation of the equinoxes -> Gr. apparent sid. time
    
    if(calc.eq.3) return
    
    
    call eq2horiz(ra,dec,agst, hh,az,alt)
    planpos(8)  = rev(hh)  ! Geocentric hour angle
    planpos(9)  = rev(az)  ! Geocentric azimuth
    planpos(10) = alt      ! Geocentric altitude
    
  end subroutine sunpos_la
  !*********************************************************************************************************************************
  
  
  
end module TheSky_planets
!***********************************************************************************************************************************
