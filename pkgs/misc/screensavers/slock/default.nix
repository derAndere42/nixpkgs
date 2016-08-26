{ stdenv, fetchurl, fetchpatch, xproto, libX11, libXext, libXrandr }:
stdenv.mkDerivation rec {
  name = "slock-1.3";
  src = fetchurl {
    url = "http://dl.suckless.org/tools/${name}.tar.gz";
    sha256 = "065xa9hl7zn0lv2f7yjxphqsa35rg6dn9hv10gys0sh4ljpa7d5s";
  };
  patches = [
    (fetchpatch {
      url = "http://s1m0n.dft-labs.eu/files/slock/slock.c.patch";
      addPrefixes = true;
      sha256 = "1g79y8yi04lnw9pyydxjh5hrw6cyqg2l0h5nv8qz62w844n4psi6";
    })
  ];
  buildInputs = [ xproto libX11 libXext libXrandr ];
  installFlags = "DESTDIR=\${out} PREFIX=";
  meta = with stdenv.lib; {
    homepage = http://tools.suckless.org/slock;
    description = "Simple X display locker";
    longDescription = ''
      Simple X display locker. This is the simplest X screen locker.
    '';
    license = licenses.mit;
    maintainers = with maintainers; [ astsmtl ];
    platforms = platforms.linux;
  };
}
