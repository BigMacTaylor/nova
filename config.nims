# config.nims

switch("define", "ssl")

if defined(release) or defined(danger):
  switch("define", "strip")
  switch("define", "danger")
  switch("opt", "speed")
  switch("passL", "-s")
