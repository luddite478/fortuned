import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer_state.dart';

class CellSettingsWidget extends StatelessWidget {
  const CellSettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive sizes based on available space - INHERIT from parent
            final panelHeight = constraints.maxHeight;
            
            // Padding & ratios
            final padding = panelHeight * 0.03;

            final innerHeight = panelHeight - padding * 2;
            final borderThickness = 1.0;
            final innerHeightAdj = innerHeight - borderThickness * 2;

            const headerRatio = 0.25;
            const footerRatio = 0.13;
            const spacingRatio = 0.02;

            final headerHeight = innerHeightAdj * headerRatio;
            final footerHeight = innerHeightAdj * footerRatio;
            final spacingHeight = innerHeightAdj * spacingRatio;
            final volumeControlHeight = innerHeightAdj - headerHeight - footerHeight - 2 * spacingHeight;

            final headerFontSize = (headerHeight * 0.35).clamp(10.0, 14.0);
            final labelFontSize = (headerHeight * 0.25).clamp(8.0, 11.0);
            final closeButtonSize = headerHeight * 0.8;
            final iconSize = (closeButtonSize * 0.5).clamp(12.0, 18.0);
            
            // Header element percentages (should add up to 100%)
            const double textAreaPercent = 25.0;     // Text area (Sample Settings + info)
            const double volButtonPercent = 13.0;    // VOL button
            const double eqButtonPercent = 13.0;      // EQ button
            const double rvbButtonPercent = 13.0;    // RVB button
            const double dlyButtonPercent = 13.0;    // DLY button
            const double delButtonPercent = 13.0;    // DEL button
            const double closeButtonPercent = 10.0;  // Close button
            
            // Get current cell info
            final selectedCell = sequencer.selectedCellForSettings;
            final hasCellSelected = selectedCell != null;
            final cellSample = hasCellSelected ? sequencer.gridSamples[selectedCell] : null;
            final cellHasSample = cellSample != null;
            
            return Container(
              padding: EdgeInsets.all(padding),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.purpleAccent.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  // Header – 25 %
                  Expanded(
                    flex: 25,
                    child: LayoutBuilder(
                      builder: (context, headerConstraints) {
                        final headerWidth = headerConstraints.maxWidth;
                        return Row(
                          children: [
                            // Cell info
                            SizedBox(
                              width: headerWidth * (textAreaPercent / 100),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Cell Settings',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: headerFontSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: padding * 0.2),
                                  Text(
                                    hasCellSelected 
                                        ? cellHasSample 
                                            ? 'Cell ${_getCellPosition(selectedCell!, sequencer)} - Sample ${String.fromCharCode(65 + cellSample!)}'
                                            : 'Cell ${_getCellPosition(selectedCell!, sequencer)} - Empty'
                                        : 'No cell selected',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: labelFontSize,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            
                            // VOL button
                            SizedBox(
                              width: headerWidth * (volButtonPercent / 100),
                              child: _buildSettingsButton('VOL', true, headerHeight * 0.7, labelFontSize),
                            ),
                            
                            // EQ button
                            SizedBox(
                              width: headerWidth * (eqButtonPercent / 100),
                              child: _buildSettingsButton('EQ', false, headerHeight * 0.7, labelFontSize),
                            ),
                            
                            // RVB button
                            SizedBox(
                              width: headerWidth * (rvbButtonPercent / 100),
                              child: _buildSettingsButton('RVB', false, headerHeight * 0.7, labelFontSize),
                            ),
                            
                            // DLY button
                            SizedBox(
                              width: headerWidth * (dlyButtonPercent / 100),
                              child: _buildSettingsButton('DLY', false, headerHeight * 0.7, labelFontSize),
                            ),
                            
                            // DEL button
                            SizedBox(
                              width: headerWidth * (delButtonPercent / 100),
                              child: _buildSettingsButton('DEL', false, headerHeight * 0.7, labelFontSize),
                            ),
                            
                            // Close button
                            SizedBox(
                              width: headerWidth * (closeButtonPercent / 100),
                              child: GestureDetector(
                                onTap: () => sequencer.setShowCellSettings(false),
                                child: Container(
                                  height: headerHeight * 0.7,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(headerHeight * 0.7 * 0.15),
                                    border: Border.all(
                                      color: Colors.grey.withOpacity(0.4),
                                      width: 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.close,
                                      color: Colors.grey,
                                      size: iconSize,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  
                  // Spacer 2 %
                  const Spacer(flex: 2),
                  
                  Expanded(
                    flex: 60,
                    child: LayoutBuilder(
                      builder: (context, innerConstraints) {
                        final volumeHeight = innerConstraints.maxHeight;
                        return (hasCellSelected && cellHasSample)
                            ? _buildVolumeControl(sequencer, selectedCell!, volumeHeight, padding, labelFontSize)
                            : _buildNoCellMessage(volumeHeight, labelFontSize);
                      },
                    ),
                  ),
                  
                  // Spacer 2 %
                  const Spacer(flex: 2),
                
                ],
              ),
            );
          },
        );
      },
    );
  }
  
  Widget _buildVolumeControl(SequencerState sequencer, int cellIndex, double height, double padding, double fontSize) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding * 0.4, vertical: padding * 0.2),
      decoration: BoxDecoration(
        color: Colors.purpleAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(padding * 0.5),
        border: Border.all(
          color: Colors.purpleAccent.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Volume label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Volume',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${(sequencer.getCellVolume(cellIndex) * 100).round()}%',
                style: TextStyle(
                  color: Colors.purpleAccent,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          
          SizedBox(height: padding * 0.2),
          
          // Volume slider
          Builder(
            builder: (context) => SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.purpleAccent,
                inactiveTrackColor: Colors.grey.withOpacity(0.3),
                thumbColor: Colors.purpleAccent,
                trackHeight: (height * 0.06).clamp(2.0, 4.0),
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: (height * 0.04).clamp(8.0, 12.0)),
              ),
              child: Slider(
                value: sequencer.getCellVolume(cellIndex),
                onChanged: (value) => sequencer.setCellVolume(cellIndex, value),
                min: 0.0,
                max: 1.0,
                divisions: 100,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNoCellMessage(double height, double fontSize) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.grid_off,
              color: Colors.grey,
              size: height * 0.3,
            ),
            SizedBox(height: height * 0.1),
            Text(
              'Tap a cell with a sample to configure',
              style: TextStyle(
                color: Colors.grey,
                fontSize: fontSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSettingsButton(String label, bool isSelected, double height, double fontSize) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isSelected ? Colors.purpleAccent : Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(height * 0.15),
        border: Border.all(
          color: Colors.grey.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
  
  String _getCellPosition(int cellIndex, SequencerState sequencer) {
    final row = cellIndex ~/ sequencer.gridColumns;
    final col = cellIndex % sequencer.gridColumns;
    return '${row + 1}:${col + 1}';
  }
} 