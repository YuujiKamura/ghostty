import sys, time
# Print some text
print('ABCDEFGHIJ')
print('KLMNOPQRST')
# Move cursor up 2 lines, right 3 columns (to 'D')
sys.stdout.write('\033[2A\033[4G')
sys.stdout.flush()
# Wait for user to inspect
time.sleep(30)
