# Logistics Tracking Smart Contract
=====================================

This project is a smart contract built on the Stacks blockchain that enables the creation, tracking, and management of shipments. The contract uses Clarity, a smart contract language, to define the rules and logic for the shipment tracking process.

## Features
------------

* Create new shipments with unique IDs
* Track shipment status (pending, in-transit, delivered, disputed)
* Validate shipment creation inputs (fee, recipient, carrier, origin, destination, dispute period)
* Ensure recipient is not the sender
* Ensure carrier is different from sender and recipient
* Validate origin and destination are not empty
* Validate dispute period

## Getting Started
-------------------

To get started with this project, you'll need to have the following installed:

* Clarity compiler
* Stacks blockchain node

You can then deploy the contract to the Stacks blockchain using the `clarinet` command-line tool.

## Usage
---------

To create a new shipment, call the `create-shipment` function with the required parameters:

* `shipment-id`: a unique ID for the shipment
* `recipient`: the recipient's principal
* `carrier`: the carrier's principal
* `origin`: the origin of the shipment (string-ascii 50)
* `destination`: the destination of the shipment (string-ascii 50)
* `fee`: the fee for the shipment (uint)
* `dispute-period`: the dispute period for the shipment (uint)

You can then track the shipment status by calling the `get-shipment-status` function with the shipment ID.

<!-- ## Contributing
--------------

Contributions to this project are welcome! If you'd like to contribute, please fork the repository and submit a pull request with your changes.

## License
----------

This project is licensed under the ISC license. See the [LICENSE.md](LICENSE.md) file for details. -->