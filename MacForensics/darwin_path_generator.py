from __future__ import print_function
import binascii


def GetDarwinPath(uuid, uid):
    '''Returns DARWIN_USER_FOLDER path constructed from UUID and UID for 
       osx older than Mavericks(10.9)'''
    charset ='+-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    uuid = uuid.replace('-', '') # strip '-' if present
    #Convert uid to hex 8 byte string
    uid = '{:08x}'.format(int(uid)) # input uid may be int or string (decimal)
    hex_string = uuid + uid
    binary_string = ''.join('{0:04b}'.format(int(c, 16)) for c in hex_string) # get binary string
    
    size = len(binary_string)
    darwin_path = ''
    for x in range(0, size, 6):
        index = binary_string[x:x+6]
        darwin_path += charset[int(index, 2)]
        if x == 6:
            darwin_path += '/' + darwin_path
    return darwin_path

def GetDarwinPath2(uuid, uid):
    '''Returns DARWIN_USER_FOLDER path constructed from UUID and UID.
       This is the algorithm for newer osx - Mavericks(10.9) thru Sierra(10.12)'''
    charset ='0123456789_bcdfghjklmnpqrstvwxyz'
    uuid = uuid.replace('-', '') # strip '-' if present
    #Convert uid to hex 8 byte string
    uid = '{:08x}'.format(int(uid)) # input uid may be int or string (decimal)
    hex_string = uuid + uid
    binary_string = ''.join('{0:04b}'.format(int(c, 16)) for c in hex_string) # get binary string
    
    size = len(binary_string)
    darwin_path = ''
    for x in range(0, size, 5):
        index = binary_string[x:x+5]
        darwin_path += charset[int(index, 2)]
        if x == 5:
            darwin_path += '/'
    return darwin_path

#print(GetDarwinPath2('3CEEF7A5-A3D9-47DC-82C1-8E386A1EA83B', 502))

# Computing path for root user
root_uuid='FFFFEEEEDDDDCCCCBBBBAAAA00000000'
root_uid = 0

path_on_older_mac = GetDarwinPath(root_uuid, root_uid)
path_on_newer_mac = GetDarwinPath2(root_uuid, root_uid)

print('Darwin folder path for root on older macs is /var/folders/' + path_on_older_mac)
print('Darwin folder path for root on newer macs is /var/folders/' + path_on_newer_mac)
