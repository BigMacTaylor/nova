# config.nims

--define:ssl

if defined(release) or defined(danger):
  --define:release
  --define:danger
  --define:strip
  --opt:speed
