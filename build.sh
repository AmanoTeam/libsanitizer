#!/bin/bash

set -eu

declare -r install_prefix='/tmp/libsanitizer'

declare -r workdir="${PWD}"

declare -r libtool_file="${workdir}/libstdc++.la"

declare -r gcc_tarball='/tmp/gcc.tar.gz'
declare -r gcc_directory='/tmp/gcc-releases-gcc-15'

declare -r libsanitizer_directory="${gcc_directory}/libsanitizer"

declare -r optflags='-w -O2 -g'
declare -r linkflags='-s'

declare -r max_jobs='40'

declare -ra asan_libraries=(
	'libasan'
	'libhwasan'
	'liblsan'
	'libtsan'
	'libubsan'
)

if ! [ -f "${gcc_tarball}" ]; then
	curl \
		--url 'https://github.com/gcc-mirror/gcc/archive/refs/heads/releases/gcc-15.tar.gz' \
		--retry '30' \
		--retry-all-errors \
		--retry-delay '0' \
		--retry-max-time '0' \
		--location \
		--silent \
		--output "${gcc_tarball}"
	
	tar \
		--directory="$(dirname "${gcc_directory}")" \
		--extract \
		--file="${gcc_tarball}"
	
	patch --directory="${gcc_directory}" --strip='1' --input="${workdir}/patches/0001-Fix-libsanitizer-build.patch"
	patch --directory="${gcc_directory}" --strip='1' --input="${workdir}/patches/0001-Skip-FILE64_FLAGS-for-Android-MIPS-targets.patch"
	patch --directory="${gcc_directory}" --strip='1' --input="${workdir}/submodules/pino/patches/0001-Disable-SONAME-versioning-for-all-target-libraries.patch"
	patch --directory="${gcc_directory}" --strip='1' --input="${workdir}/submodules/pino/patches/0001-Avoid-relying-on-dynamic-shadow-when-building-libsan.patch"
fi

# Follow Debian's approach for removing hardcoded RPATH from binaries
# https://wiki.debian.org/RpathIssue
sed \
	--in-place \
	--regexp-extended \
	's/(hardcode_into_libs)=.*$/\1=no/' \
	"${gcc_directory}/libsanitizer/configure"

[ -d "${libsanitizer_directory}/build" ] || mkdir "${libsanitizer_directory}/build"

cd "${libsanitizer_directory}/build"

mkdir --parent "${libsanitizer_directory}/libstdc++-v3/src"

declare file="$(${CROSS_COMPILE_TRIPLET}-g++ --print-file-name='libstdc++.so')"
declare -r library_directory="$(dirname "${file}")"

cp "${libtool_file}" "${libsanitizer_directory}/libstdc++-v3/src"

echo "libdir='${library_directory}'" >> "${libsanitizer_directory}/libstdc++-v3/src/libstdc++.la"

../configure \
	--disable-multilib \
	--with-gcc-major-version-only \
	--enable-shared \
	--host="${CROSS_COMPILE_TRIPLET}" \
	--prefix="${install_prefix}" \
	CFLAGS="${optflags}" \
	CXXFLAGS="${optflags} -D_ABIN32=2" \
	LDFLAGS="${linkflags}"

make --jobs="${max_jobs}"
make install

if [ -d "${install_prefix}/lib64" ]; then
	mv "${install_prefix}/lib64/"* "${install_prefix}/lib"
	rmdir "${install_prefix}/lib64"
fi

