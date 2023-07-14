# zerotier-add-via-api
Add Linux node via API using a shell script

To execute the script, you can follow these steps:

Open a text editor and paste the cleaned up script into a new file. Save the file with a .sh extension, for example, zerotier_autojoin.sh.

Open a terminal and navigate to the directory where you saved the script.

Make the script executable by running the following command:
```
chmod +x zerotier_autojoin.sh
```
Run the script by executing the following command:


```
./zerotier_autojoin.sh --network=<32charalphanum> --api=<32charalphanum> [ <other options: see below> ]
```
Replace <32charalphanum> with the appropriate values for the network ID and API key. You can also specify additional options as needed.

For example:
```
./zerotier_autojoin.sh --network=0123456789abcdef --api=0123456789abcdef
```

Note that you should provide valid values for the network ID and API key.

The script will join the specified ZeroTier network and, if an API key is provided, authorize the device. You will see the progress and output of the script in the terminal.

Make sure you have the curl, jq, and zerotier-one applications installed on your system before running the script.
