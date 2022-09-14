# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   module Test
      describe MockTask do
         context '#run?' do
            it 'should be false before running' do
               instance = described_class.new

               expect(instance.run?).to be_falsey
            end

            it 'should be true after running' do
               instance = described_class.new

               instance.run
               expect(instance.run?).to be_truthy
            end
         end
      end

      describe MockDataTask do
         it 'should accept data' do
            instance = described_class.new

            instance.data = 5

            expect(instance.data).to eq 5
         end
      end
   end
end
