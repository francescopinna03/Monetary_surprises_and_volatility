function hash = File_sha256(filePath)
%FILE_SHA256 Return the lowercase SHA-256 digest of a local file.

    filePath = char(string(filePath));
    fid = fopen(filePath, 'r');
    if fid < 0
        error('FILE_SHA256_READ: unable to open %s.', filePath);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = fread(fid, Inf, '*uint8');
    digest = java.security.MessageDigest.getInstance('SHA-256');
    digest.update(bytes);
    raw = typecast(digest.digest(), 'uint8');
    hash = lower(string(reshape(dec2hex(raw, 2).', 1, [])));
end
