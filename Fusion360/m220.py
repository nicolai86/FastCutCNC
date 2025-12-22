# simCNC doesn't allow named parameter passing,
# so this needs to be invoked like
# #1000=60 M220
# if you want to set FRO to 60%
percentage = d.getMachineParam(1000)
d.setFRO(int(percentage))

print(f"Feed rate override set to {int(percentage)}%")